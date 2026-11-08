"""Verify the bundled View Count plugin and the content view counting it does.

After a response, the plugin's middleware counts a visitor's GET of a
published content page, keeps the counts and writes them with its job once a
minute. These tests make that job due instead of waiting for it. The test
client sends no User-Agent, so only requests that send a browser's are views.
"""

import json
import os
import secrets
import time

from admin_mcp import call, issue, succeeded
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore

PLUGIN = "/admin/plugins/plugin-view-count"
PAGE = "/admin/view-counts"
DATA = f"{PAGE}/data"
# The plugin's own job, `<pluginId>:<key>`, that writes the counted views.
JOB = "d47e7c67-745e-4783-8c9c-1d95c3931ab0:flush"
BROWSER = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}
PAGE_DATA = {"X-Well-Data": "true", "Accept": "application/json"}


def published(fixtures, count):
    """The IDs and public paths of `count` published entries."""
    rows = fixtures.rows(
        "items",
        ["id", "slug"],
        [("status", "=", "published"), ("content_type", "=", "entry")],
        limit=count,
    )
    check(len(rows) == count, "The site has too few published entries")
    return [(row["id"], f"/content/{row['slug']}") for row in rows]


def flush(fixtures):
    """Makes the plugin's job that writes counted views due now."""
    now = int(time.time() * 1000)
    fixtures.update("scheduled_jobs", {"next_epoch": now - 1000}, [("id", "=", JOB)])


def wait_for(read, expected, message, timeout=30):
    deadline = time.monotonic() + timeout
    value = read()
    while value != expected and time.monotonic() < deadline:
        time.sleep(0.5)
        value = read()
    check(value == expected, f"{message}: {value!r} instead of {expected!r}")
    return value


def data(owner, query=""):
    status, headers, body = owner.request(f"{DATA}{query}")
    check(status == 200, f"The view count data returned {status}: {body[:200]}")
    check(headers.get("content-type", "").startswith("application/json"), "The data is not JSON")
    return json.loads(body)


def views_of(owner, content_id):
    items = data(owner, f"?content={content_id}")["items"]
    return items[0]["views"] if items else 0


def visit(path, headers=None, method="GET"):
    """A request from a new browser, without the cookies of a signed-in member."""
    status = Client().request(path, method, extra_headers={**BROWSER, **(headers or {})})[0]
    check(status == 200, f"{method} {path} returned {status}")


def configure(owner, show, position="content.after", countries=False):
    owner.request(f"{PLUGIN}/settings")
    values = {
        "show_count": "true" if show else "false",
        "position": position,
        "count_countries": "true" if countries else "false",
    }
    status = owner.request(f"{PLUGIN}/settings", "POST", values)[0]
    check(status == 303, f"Could not save the View Count settings: {status}")


def blocks(path):
    """The extension blocks a public page shows, read by a client that is not a browser."""
    status, _, body = Client().request(path, extra_headers=PAGE_DATA)
    check(status == 200, f"{path} returned {status}")
    return json.loads(body)["props"]["extensions"]["blocks"]


def verify_counting(owner, fixtures, first, second):
    first_id, first_path = first
    second_id, second_path = second
    check(views_of(owner, first_id) == 0, "A content item had views before anyone visited it")
    member = owner.cookies.get("cms_member")
    check(member == "1", "Signing in did not mark the member's browser")
    # None of these is a visitor's view of the page.
    visit(first_path, method="HEAD")
    visit(first_path, {"User-Agent": "Mozilla/5.0 (compatible; Googlebot/2.1)"})
    visit(first_path, {"Sec-Purpose": "prefetch;prerender"})
    visit(first_path, {"Cookie": "cms_member=1"})
    check(Client().request(first_path)[0] == 200, "The content page did not render")
    status = owner.request(first_path, extra_headers=BROWSER)[0]
    check(status == 200, "The content page did not render for the owner")
    preview = f"/admin/themes/theme-simple/preview/frame{first_path}"
    check(owner.request(preview, extra_headers=BROWSER)[0] == 200, "The theme preview failed")
    check(Client().request("/content/no-such-content", extra_headers=BROWSER)[0] == 404, "404")
    # Three real views of the first item and two of the second.
    for _ in range(3):
        visit(first_path)
    for _ in range(2):
        visit(second_path)
    flush(fixtures)
    wait_for(lambda: views_of(owner, first_id), 3, "The first item's views")
    wait_for(lambda: views_of(owner, second_id), 2, "The second item's views")
    print("PASS Visitors' views are counted once a minute by content item", flush=True)
    print(
        "PASS HEAD requests, crawlers, speculative loads, members, previews and clients that "
        "are not browsers are not counted",
        flush=True,
    )
    visit(first_path)
    flush(fixtures)
    wait_for(lambda: views_of(owner, first_id), 4, "A later view did not add to the count")
    print("PASS Later views add to the stored count", flush=True)


def verify_display(owner, first):
    _, path = first
    check(
        not [block for block in blocks(path) if "view" in block["content"]],
        "The view count was shown before the setting allowed it",
    )
    configure(owner, True)
    shown = [block for block in blocks(path) if block["slot"] == "content.after"]
    check(
        any(block["content"] == "4 views" for block in shown),
        f"The content page did not show its count: {shown}",
    )
    html = Client().request(path)[2]
    check("4 views" in html, "The theme did not render the count block")
    configure(owner, True, "content.before")
    shown = [block for block in blocks(path) if block["content"] == "4 views"]
    check(
        len(shown) == 1 and shown[0]["slot"] == "content.before",
        "The count did not move before the content",
    )
    configure(owner, False)
    check(
        not [block for block in blocks(path) if block["content"] == "4 views"],
        "The count stayed on the page after the setting was turned off",
    )
    print("PASS Content pages show their count when the setting asks for it", flush=True)


def verify_data(owner, first, second):
    first_id, _ = first
    second_id, _ = second
    listing = data(owner, "?limit=1")
    check(
        len(listing["items"]) == 1 and listing["items"][0]["contentId"] == first_id,
        f"The most viewed item was not first: {listing}",
    )
    check(listing["views"] >= 6 and listing["contentItems"] >= 2, "The totals are missing")
    item = listing["items"][0]
    check(
        set(item) == {"contentId", "title", "type", "url", "views"}
        and item["url"].startswith("/content/"),
        f"An item has unexpected fields: {item}",
    )
    check(listing["next"], "The first page has no cursor to the next")
    following = data(owner, f"?limit=1&cursor={listing['next']}")
    check(
        following["items"][0]["contentId"] == second_id,
        f"The cursor did not continue the list: {following}",
    )
    for query in ["?limit=0", "?limit=101", "?content=abc", "?content=-1", "?content=1%0A"]:
        status = owner.request(f"{DATA}{query}")[0]
        check(status == 422, f"The data accepted {query}: {status}")
    page = owner.request(PAGE)[2]
    check(item["title"] in page and "View counts" in page, "The administration page lists no views")
    dashboard = owner.request("/admin")[2]
    check(
        f'href="{PAGE}"' in dashboard and f'href="{PAGE}/countries"' in dashboard,
        "The menu has no links to the plugin's pages",
    )
    check("views in total" in owner.request("/admin")[2], "The dashboard shows no total")
    print("PASS The page, the menu, the dashboard and the JSON data list the counts", flush=True)

    connection = issue(owner)
    public = Client()
    result = succeeded(call(public, connection, "plugin_view_count_views", {"content": first_id}))
    check(
        result["status"] == 200 and result["data"]["items"][0]["views"] == 4,
        f"The MCP tool did not answer the count: {result}",
    )
    print("PASS The MCP tool reads the counts", flush=True)


def verify_permissions(owner):
    password = secrets.token_urlsafe(18)
    email = f"views-{secrets.token_hex(4)}@example.test"
    member = {"name": "Views Editor", "email": email, "role": "editor", "password": password}
    status = owner.request("/admin/team/save", "POST", {**member, "active": "1"})[0]
    check(status == 303, "Could not create an editor account")
    editor = login(email, password)
    check(editor.request(PAGE)[0] == 403, "An editor without the capability opened the page")
    check(editor.request(DATA)[0] == 403, "An editor without the capability read the data")
    check(f'href="{PAGE}"' not in editor.request("/admin")[2], "The menu link ignored the role")
    check(Client().request(DATA)[0] in (302, 303), "The data was readable without signing in")
    print("PASS Only members with the view count capability see the counts", flush=True)


def stored_views(fixtures, content_id):
    rows = fixtures.rows("view_count_totals", ["views"], [("content_id", "=", content_id)], limit=1)
    return rows[0]["views"] if rows else 0


def job_ran(fixtures):
    """Waits until the plugin's job has run since `flush` made it due."""
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        job = fixtures.rows("scheduled_jobs", ["next_epoch"], [("id", "=", JOB)], limit=1)[0]
        if job["next_epoch"] > time.time() * 1000:
            return
        time.sleep(0.5)
    raise AssertionError("The plugin's job did not run")


def verify_lifecycle(owner, fixtures, first):
    first_id, first_path = first
    visit(first_path)
    check(owner.request(f"{PLUGIN}/disable", "POST", {})[0] == 303, "disable View Count")
    check(
        stored_views(fixtures, first_id) == 5,
        "Stopping the plugin did not write the views it still kept",
    )
    check(owner.request(PAGE)[0] == 404, "The page remained after the plugin stopped")
    visit(first_path)
    check(owner.request(f"{PLUGIN}/enable", "POST", {})[0] == 303, "enable View Count")
    flush(fixtures)
    job_ran(fixtures)
    check(views_of(owner, first_id) == 5, "The counts were lost or a view counted while off")
    visit(first_path)
    flush(fixtures)
    wait_for(lambda: views_of(owner, first_id), 6, "Counting did not resume with the plugin")
    print(
        "PASS Disabling writes the kept views and stops counting; enabling resumes it",
        flush=True,
    )


def run():
    owner = Client()
    owner.request("/admin/login")
    credentials = {
        "email": os.environ["TEST_ADMIN_EMAIL"],
        "password": os.environ["TEST_ADMIN_PASSWORD"],
    }
    check(owner.request("/admin/login", "POST", credentials)[0] == 303, "View Count owner login")
    with FixtureStore.from_environment() as fixtures:
        installed = fixtures.rows(
            "cms_packages", ["enabled"], [("id", "=", "plugin-view-count")], limit=1
        )
        check(len(installed) == 1, "The View Count plugin is not installed with the site")
        check(installed[0]["enabled"] == 1, "The View Count plugin is not enabled by default")
        first, second = published(fixtures, 2)
        try:
            verify_counting(owner, fixtures, first, second)
            verify_display(owner, first)
            verify_data(owner, first, second)
            verify_permissions(owner)
            verify_lifecycle(owner, fixtures, first)
        finally:
            owner.request(f"{PLUGIN}/enable", "POST", {})
            configure(owner, False)


if __name__ == "__main__":
    run()
