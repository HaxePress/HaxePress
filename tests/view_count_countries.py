"""Verify the View Count plugin's counts by country and the visitor country it reads.

Counting by country is a plugin setting, off by default. The country comes
from `CF-IPCountry`, which the Cloudflare plugin trusts only on connections
from Cloudflare. The tests reach the site from 127.0.0.1, which is not a
Cloudflare address, so the Cloudflare plugin's Tunnel setting is what lets
their header count.
"""

import json
import os

from admin_mcp import call, issue, succeeded
from cloudflare import configure as tunnel
from e2e import Client, check
from fixture_store import FixtureStore
from view_count import BROWSER, configure, flush, published, views_of, wait_for

CLOUDFLARE = "/admin/plugins/plugin-cloudflare"
PAGE = "/admin/view-counts/countries"
DATA = f"{PAGE}/data"
UNKNOWN = "UNKNOWN"
NOT_COUNTING = "Views are not counted by country."
NO_SOURCE = "Countries come from the Cloudflare plugin, which is not active."


def data(owner, query=""):
    status, headers, body = owner.request(f"{DATA}{query}")
    check(status == 200, f"The country data returned {status}: {body[:200]}")
    check(headers.get("content-type", "").startswith("application/json"), "The data is not JSON")
    return json.loads(body)


def countries(owner, content_id):
    """The counted views of one content item by country."""
    items = data(owner, f"?content={content_id}&limit=100")["items"]
    return {item["country"]: item["views"] for item in items}


def visit(path, country=None):
    headers = dict(BROWSER)
    if country is not None:
        headers["CF-IPCountry"] = country
    status = Client().request(path, extra_headers=headers)[0]
    check(status == 200, f"{path} returned {status}")


def verify_default(owner, fixtures, content_id, path):
    check(data(owner)["countingCountries"] is False, "Counting by country was on by default")
    check(NOT_COUNTING in owner.request(PAGE)[2], "The page did not say countries are off")
    tunnel(owner, True)
    visit(path, "TR")
    flush(fixtures)
    wait_for(lambda: views_of(owner, content_id), 1, "The view was not counted")
    check(countries(owner, content_id) == {}, "A country was stored with the setting off")
    print("PASS By default the plugin counts views without their country", flush=True)


def verify_countries(owner, fixtures, content_id, path):
    configure(owner, False, countries=True)
    check(data(owner)["countingCountries"] is True, "The country setting did not reach the plugin")
    check(NOT_COUNTING not in owner.request(PAGE)[2], "The page still said countries are off")
    tunnel(owner, False)
    visit(path, "TR")
    visit(path)
    flush(fixtures)
    wait_for(
        lambda: countries(owner, content_id),
        {UNKNOWN: 2},
        "A country sent from outside Cloudflare was used",
    )
    print("PASS CF-IPCountry from a connection outside Cloudflare counts as UNKNOWN", flush=True)

    tunnel(owner, True)
    visit(path, "TR")
    visit(path, "TR")
    visit(path, "de")
    visit(path, " US ")
    for ignored in ["XX", "T1", "TUR", "1A", ""]:
        visit(path, ignored)
    flush(fixtures)
    expected = {UNKNOWN: 7, "TR": 2, "DE": 1, "US": 1}
    wait_for(lambda: countries(owner, content_id), expected, "The trusted countries")
    check(views_of(owner, content_id) == 12, "The views by country did not add to the total")
    print(
        "PASS Trusted connections count by country; XX, T1 and malformed codes count as UNKNOWN",
        flush=True,
    )

    check(owner.request(f"{CLOUDFLARE}/disable", "POST", {})[0] == 303, "disable Cloudflare")
    try:
        visit(path, "TR")
        flush(fixtures)
        expected[UNKNOWN] += 1
        wait_for(
            lambda: countries(owner, content_id),
            expected,
            "A country counted without the Cloudflare plugin",
        )
        check(NO_SOURCE in owner.request(PAGE)[2], "The page did not say Cloudflare is missing")
        check(data(owner)["countrySourceActive"] is False, "The data hid the missing source")
    finally:
        check(owner.request(f"{CLOUDFLARE}/enable", "POST", {})[0] == 303, "enable Cloudflare")
    check(NO_SOURCE not in owner.request(PAGE)[2], "The warning stayed with Cloudflare active")
    print("PASS Without the Cloudflare plugin every view counts as UNKNOWN", flush=True)
    return expected


def verify_data(owner, fixtures, content_id, other_id, other_path, expected):
    visit(other_path, "TR")
    flush(fixtures)
    wait_for(lambda: countries(owner, other_id), {"TR": 1}, "The second item's country")
    from_turkey = data(owner, "?country=TR")
    check(
        [item["contentId"] for item in from_turkey["items"]] == [content_id, other_id]
        and from_turkey["total"] == 2,
        f"The country filter listed other rows: {from_turkey}",
    )
    item = from_turkey["items"][0]
    check(
        set(item) == {"contentId", "title", "type", "url", "country", "views"}
        and item["views"] == expected["TR"]
        and item["url"].startswith("/content/"),
        f"A row has unexpected fields: {item}",
    )
    first = data(owner, f"?content={content_id}&limit=1")
    check(
        first["items"][0]["country"] == UNKNOWN and first["next"] and first["total"] == 4,
        f"The most viewed country was not first: {first}",
    )
    rest = data(owner, f"?content={content_id}&limit=3&cursor={first['next']}")
    check(
        rest["items"][0]["country"] == "TR" and rest["next"] is None,
        f"The cursor did not continue the list: {rest}",
    )
    for query in ["?country=tr", "?country=TUR", "?country=TR%0A", "?limit=0", "?content=x"]:
        status = owner.request(f"{DATA}{query}")[0]
        check(status == 422, f"The data accepted {query}: {status}")
    page = owner.request(f"{PAGE}?country=TR")[2]
    check(
        item["title"] in page and f"{PAGE}?content={content_id}&amp;country=TR" in page,
        "The page did not list the filtered rows with their links",
    )
    print("PASS The page, its filters and the JSON data list the views by country", flush=True)

    connection = issue(owner)
    result = succeeded(
        call(Client(), connection, "plugin_view_count_country_views", {"country": "DE"})
    )
    rows = result["data"]["items"]
    check(
        result["status"] == 200 and [row["country"] for row in rows] == ["DE"],
        f"The MCP tool did not filter by country: {result}",
    )
    print("PASS The MCP tool reads the views by country", flush=True)


def verify_setting(owner, fixtures, content_id, path, expected):
    total = views_of(owner, content_id)
    configure(owner, False, countries=False)
    visit(path, "TR")
    flush(fixtures)
    wait_for(lambda: views_of(owner, content_id), total + 1, "The view was not counted")
    check(
        countries(owner, content_id) == expected,
        "A country was counted after the setting was turned off, or the counts were lost",
    )
    configure(owner, False, countries=True)
    visit(path, "TR")
    flush(fixtures)
    expected["TR"] += 1
    wait_for(lambda: countries(owner, content_id), expected, "Counting by country did not resume")
    print("PASS Turning the setting off stops country counts and keeps them", flush=True)


def run():
    owner = Client()
    owner.request("/admin/login")
    credentials = {
        "email": os.environ["TEST_ADMIN_EMAIL"],
        "password": os.environ["TEST_ADMIN_PASSWORD"],
    }
    check(owner.request("/admin/login", "POST", credentials)[0] == 303, "Country views login")
    with FixtureStore.from_environment() as fixtures:
        # The view count suite uses the first two entries; these two have no views yet.
        entries = published(fixtures, 4)
        (content_id, path), (other_id, other_path) = entries[2], entries[3]
        try:
            verify_default(owner, fixtures, content_id, path)
            expected = verify_countries(owner, fixtures, content_id, path)
            verify_data(owner, fixtures, content_id, other_id, other_path, expected)
            verify_setting(owner, fixtures, content_id, path, expected)
        finally:
            owner.request(f"{CLOUDFLARE}/enable", "POST", {})
            configure(owner, False)
            tunnel(owner, False)


if __name__ == "__main__":
    run()
