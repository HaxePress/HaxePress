"""Verify the columns of admin content lists: order, visibility, sorting and plugin columns.

Every member arranges and sorts the columns of a collection's list for
themselves. The View Count plugin adds a Views column through
ContentColumns; the list reads and sorts it in SQL, pages with a cursor on
the sorted value, and loses it while the plugin is inactive.
"""

import base64
import json
import os
import secrets
import urllib.parse

from cms_content import props
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore

LIST = "/admin/content"
VIEWS = "plugin-view-count.views"
PLUGIN = "/admin/plugins/plugin-view-count"
SEARCH = "Columns fixture"
COUNT = 45


def keys(page):
    return [column["key"] for column in page["columns"]]


def setting_keys(page):
    return [setting["key"] for setting in page["columnSettings"]]


def listed(sort="", direction=""):
    parameters = {"q": SEARCH}
    if sort:
        parameters["sort"] = sort
        parameters["dir"] = direction
    return f"{LIST}?{urllib.parse.urlencode(parameters)}"


def save_columns(client, page, order=None, visible=None, move="", reset=False):
    order = order or setting_keys(page)
    shown = (
        visible
        if visible is not None
        else [setting["key"] for setting in page["columnSettings"] if setting["visible"]]
    )
    data = {
        "order": ",".join(order),
        "q": page["query"],
        "status": page["status"],
        "sort": page["sort"],
        "dir": page["direction"],
    }
    for index, key in enumerate(order):
        if key in shown:
            data[f"visible_{index}"] = key
    if move:
        data["move"] = move
    if reset:
        data["reset"] = "1"
    status, headers, body = client.request(f"{LIST}/columns", "POST", data)
    check(status == 303, f"Saving the list columns returned {status}: {body[:200]}")
    return headers["location"]


def walk(client, path):
    """The row IDs of every page of a list, following its next links."""
    ids = []
    pages = []
    url = path
    while url:
        page = props(client, url)
        check(len(page["items"]) <= 20, "A list page held more than 20 rows")
        ids.extend(item["id"] for item in page["items"])
        pages.append(page)
        url = page["pagination"]["next"]
        check(len(pages) <= 10, "A list's next links did not end")
    return ids, pages


def cell(page, item_id, key):
    position = keys(page).index(key)
    for item in page["items"]:
        if item["id"] == item_id:
            return item["cells"][position]["text"]
    raise AssertionError(f"Item {item_id} is not on the page")


def create_items(fixtures):
    records = [
        {
            "title": f"{SEARCH} {str(index).zfill(2)}",
            "slug": f"columns-fixture-{str(index).zfill(2)}",
            "excerpt": "",
            "content": "Column fixture",
            "category": "",
            "image": "",
            "image_alt": "",
            "status": "draft",
            "featured": 0,
            "reading_minutes": 1,
            "published_at": None,
            "created_at": "2026-11-01 08:00:00",
            "updated_at": f"2026-11-01 08:{str(index).zfill(2)}:00",
        }
        for index in range(COUNT)
    ]
    ids = fixtures.create("items", records)
    # Thirty items have counts, with ties; fifteen have none and sort lowest.
    views = {item_id: (index % 7) * 3 for index, item_id in enumerate(ids) if index % 3 != 2}
    fixtures.create(
        "view_count_totals",
        [{"content_id": item_id, "views": count} for item_id, count in views.items()],
    )
    return ids, views


def expected_by_views(ids, views, descending):
    counted = sorted(
        (item_id for item_id in ids if item_id in views),
        key=lambda item_id: (views[item_id], item_id),
        reverse=descending,
    )
    uncounted = sorted((item_id for item_id in ids if item_id not in views), reverse=descending)
    return counted + uncounted if descending else uncounted + counted


def verify_sorting(owner, fixtures, ids, views):
    default = props(owner, listed())
    order = keys(default)
    check(order[0] == "title" and order[-1] == "updated", f"Unexpected default columns: {order}")
    check(
        VIEWS in order and order.index(VIEWS) == len(order) - 2,
        f"The Views column is not shown before Last updated by default: {order}",
    )
    newest, _ = walk(owner, listed())
    check(newest == sorted(ids, reverse=True), "The list is not newest first by default")
    for descending in [True, False]:
        direction = "desc" if descending else "asc"
        seen, pages = walk(owner, listed(VIEWS, direction))
        check(
            seen == expected_by_views(ids, views, descending),
            f"Sorting by views {direction} returned {seen}",
        )
        check(len(pages) == 3, f"Sorting by views {direction} did not page in threes")
        previous = props(owner, pages[2]["pagination"]["previous"])
        check(
            [item["id"] for item in previous["items"]]
            == [item["id"] for item in pages[1]["items"]],
            f"The previous link of a views {direction} page returned other rows",
        )
        sorted_column = next(column for column in pages[0]["columns"] if column["key"] == VIEWS)
        check(
            sorted_column["sorted"] == ("descending" if descending else "ascending"),
            "The sorted heading does not say its direction",
        )
    titles, _ = walk(owner, listed("title", "asc"))
    check(titles == ids, "Sorting by title did not follow the titles")
    titles, _ = walk(owner, listed("title", "desc"))
    check(titles == list(reversed(ids)), "Sorting by title descending did not reverse it")
    page = props(owner, listed(VIEWS, "desc"))
    first = page["items"][0]["id"]
    check(cell(page, first, VIEWS) == str(views[first]), "A Views cell shows another count")
    last_page = walk(owner, listed(VIEWS, "desc"))[1][-1]
    uncounted = last_page["items"][-1]["id"]
    check(cell(last_page, uncounted, VIEWS) == "0", "An item without views does not show 0")
    fixtures.update("view_count_totals", {"views": 999}, [("content_id", "=", first)])
    check(
        cell(props(owner, listed(VIEWS, "desc")), first, VIEWS) == "999",
        "The Views column showed a cached count",
    )
    fixtures.update("view_count_totals", {"views": views[first]}, [("content_id", "=", first)])
    token = base64.urlsafe_b64encode(json.dumps(["not a number", ids[0], False]).encode())
    status = owner.request(f"{listed(VIEWS, 'desc')}&cursor={token.decode().rstrip('=')}")[0]
    check(status == 200, "A malformed views cursor broke the list")
    print("PASS Content lists sort in SQL by plugin, own and date columns across pages", flush=True)


def verify_layout(owner, fixtures, owner_id):
    page = props(owner, listed())
    default = setting_keys(page)
    shown = [key for key in keys(page) if key != "category"]
    page = props(owner, save_columns(owner, page, visible=shown))
    check("category" not in keys(page), "A hidden column is still shown")
    check(
        all(len(item["cells"]) == len(page["columns"]) for item in page["items"]),
        "Rows do not have a cell for each visible column",
    )
    page = props(owner, save_columns(owner, page, move="status:up"))
    check(setting_keys(page)[:2] == ["status", "title"], "Moving a column up did not move it")
    check(keys(page)[:2] == ["status", "title"], "The visible columns do not follow the order")
    page = props(owner, save_columns(owner, page, move=f"{VIEWS}:down"))
    order = setting_keys(page)
    check(order[-1] == VIEWS, f"Moving the Views column down did not move it: {order}")
    check(
        fixtures.count("admin_preferences", [("admin_id", "=", owner_id)]) == 1,
        "The columns were not kept as the member's own preference",
    )
    visible = [key for key in keys(page) if key != VIEWS]
    page = props(owner, save_columns(owner, page, visible=visible))
    check(VIEWS not in keys(page), "The Views column could not be hidden")
    check(owner.request(f"{PLUGIN}/disable", "POST", {})[0] == 303, "disable View Count")
    page = props(owner, listed(VIEWS, "desc"))
    check(VIEWS not in setting_keys(page), "An inactive plugin's column is still offered")
    check(page["sort"] == "", "The list sorted by an inactive plugin's column")
    page = props(owner, save_columns(owner, page, move="title:up"))
    check(owner.request(f"{PLUGIN}/enable", "POST", {})[0] == 303, "enable View Count")
    page = props(owner, listed())
    order = setting_keys(page)
    check(order[:2] == ["title", "status"], f"The order saved while inactive was lost: {order}")
    check(order[-1] == VIEWS, f"The plugin's column did not return to its place: {order}")
    check(VIEWS not in keys(page), "The plugin's column lost its hidden choice")
    page = props(owner, save_columns(owner, page, reset=True))
    check(setting_keys(page) == default, "Resetting did not restore the default columns")
    check(keys(page) == default, "Resetting did not show every column")
    print(
        "PASS Members order and hide list columns; inactive plugins keep their columns' places",
        flush=True,
    )


def verify_capability(owner, fixtures):
    key = f"columns_{secrets.token_hex(5)}"
    email = f"{key}@example.test"
    password = secrets.token_urlsafe(18)
    role = {"key": key, "name": "Columns access test", "enabled": "1"}
    try:
        check(
            owner.request("/admin/roles/create", "POST", {**role, "capabilities": '["content"]'})[0]
            == 303,
            "Could not create a content role",
        )
        member = {
            "name": "Columns member",
            "email": email,
            "password": password,
            "role": key,
            "active": "1",
        }
        check(owner.request("/admin/team/save", "POST", member)[0] == 303, "Could not add a member")
        editor = login(email, password)
        page = props(editor, listed())
        check(VIEWS not in setting_keys(page), "A member without the view count capability saw it")
        capabilities = json.dumps(["content", "view_counts"])
        check(
            owner.request(
                f"/admin/roles/{key}/save", "POST", {**role, "capabilities": capabilities}
            )[0]
            == 303,
            "Could not grant view counts",
        )
        check(VIEWS in keys(props(editor, listed())), "The view count capability did not show it")
        check(VIEWS in keys(props(owner, listed())), "Another member's columns changed")
    finally:
        fixtures.delete("admins", [("email", "=", email)])
        owner.request(f"/admin/roles/{key}/delete", "POST", {})
    print("PASS A plugin column follows its capability", flush=True)


def run():
    owner = Client()
    owner.request("/admin/login")
    credentials = {
        "email": os.environ["TEST_ADMIN_EMAIL"],
        "password": os.environ["TEST_ADMIN_PASSWORD"],
    }
    check(owner.request("/admin/login", "POST", credentials)[0] == 303, "columns owner login")
    with FixtureStore.from_environment() as fixtures:
        owner_id = fixtures.rows(
            "admins", ["id"], [("email", "=", credentials["email"].lower())], limit=1
        )[0]["id"]
        ids, views = create_items(fixtures)
        try:
            verify_sorting(owner, fixtures, ids, views)
            verify_layout(owner, fixtures, owner_id)
            verify_capability(owner, fixtures)
        finally:
            owner.request(f"{PLUGIN}/enable", "POST", {})
            fixtures.delete("admin_preferences", [("admin_id", "=", owner_id)])
            fixtures.delete("view_count_totals", [("content_id", "in", ids)])
            fixtures.delete("items", [("id", "in", ids)])


if __name__ == "__main__":
    run()
