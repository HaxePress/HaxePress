"""Exercise bounded projections and cursor queries against a larger temporary database."""

from collections import Counter
import csv
import io
import json
import os
from pathlib import Path
import urllib.parse

from content_cache import clear_content, content_entries
from e2e import Client, check
from fixture_store import FixtureStore

HEADERS = {"X-Well-Data": "true", "Accept": "application/json"}


def page(client, route, group=None):
    status, _, body = client.request(route, extra_headers=HEADERS)
    check(status == 200, f"page failed: {route} {body[:200]}")
    props = json.loads(body)["props"]
    return props[group] if group else props


def walk(client, route, field, limit, expected, category_counts=None, group=None):
    seen = []
    pages = []
    previous_items = None
    next_route = route
    for index in range(100):
        props = page(client, next_route, group)
        items = props[field]
        check(len(items) <= limit, f"unbounded page: {route}")
        check(props["pagination"]["total"] == len(expected), "incorrect filtered count")
        if category_counts is not None:
            for category in items:
                check(
                    category["items"] == category_counts.get(category["name"], 0),
                    f"category content item count is incorrect: {category['name']}",
                )
        if index == 1:
            previous = page(client, props["pagination"]["previous"], group)[field]
            check(
                [item["id"] for item in previous] == previous_items,
                "previous cursor changed ordering",
            )
        previous_items = [item["id"] for item in items]
        pages.append(previous_items)
        seen.extend(previous_items)
        next_route = props["pagination"]["next"]
        if not next_route:
            break
    else:
        raise AssertionError("pagination never ended")
    check(
        seen == expected and len(seen) == len(set(seen)),
        f"missing/duplicate/incorrect cursor rows: {route}",
    )
    for expected_page in reversed(pages[:-1]):
        previous_route = props["pagination"]["previous"]
        check(previous_route is not None, "previous pagination ended early")
        props = page(client, previous_route, group)
        check(
            [item["id"] for item in props[field]] == expected_page,
            f"backward cursor changed ordering: {route}",
        )
    check(props["pagination"]["previous"] is None, "first page has a previous cursor")


def run():
    with FixtureStore.from_environment() as fixtures:
        verify(fixtures)


def verify(fixtures):
    cache_folder = Path(os.environ["TEST_CACHE_PATH"])
    public = Client()
    admin = Client()
    admin.request("/admin/login")
    check(
        admin.request(
            "/admin/login",
            "POST",
            {
                "email": os.environ["TEST_ADMIN_EMAIL"],
                "password": os.environ["TEST_ADMIN_PASSWORD"],
            },
        )[0]
        == 303,
        "scale-test login",
    )
    stamp = "2026-11-03 12:00:00"
    marker = "BODYONLYSCALE " * 400
    dates = ["2026-01-03", "2026-01-03 00:00:00", "2025-09-10", "2025-01-01"]
    base_items = list(
        fixtures.scan("items", ["id", "status", "category", "published_at", "updated_at"])
    )
    base_categories = list(fixtures.scan("categories", ["id", "name"]))
    base_subscribers = list(fixtures.scan("subscribers", ["id"]))
    status, _, body = admin.request("/admin/subscribers/export")
    check(
        status == 200 and len(list(csv.reader(io.StringIO(body)))) == len(base_subscribers) + 1,
        "CSV export failed for the initial subscriber list (including an empty list)",
    )

    category_inputs = [
        {
            "name": f"Scale category {str(index).zfill(3)}",
            "name_key": f"scale category {str(index).zfill(3)}",
            "created_at": stamp,
            "updated_at": stamp,
        }
        for index in range(87)
    ]
    category_ids = fixtures.create("categories", category_inputs)
    content_inputs = []
    for index in range(120):
        title = f"Scale fixture {str(index).zfill(3)}"
        if index == 0:
            title += " literal_% !"
        content_inputs.append(
            {
                "title": title,
                "slug": f"scale-fixture-{str(index)}",
                "excerpt": "A bounded test content item for cursor pagination.",
                "content": marker,
                "category": (
                    "Getting started"
                    if index % 5 == 0
                    else f"Scale category {str(index % 87).zfill(3)}"
                ),
                "image": "",
                "image_alt": "",
                "status": "published" if index < 83 else "draft",
                "featured": 0,
                "reading_minutes": 3,
                "published_at": None if index % 7 == 0 else dates[index % len(dates)],
                "created_at": stamp,
                "updated_at": stamp,
            }
        )
    content_ids = fixtures.create("items", content_inputs)
    subscriber_inputs = [
        {"email": f"scale-{str(index).zfill(3)}@example.com", "created_at": stamp}
        for index in range(95)
    ]
    subscriber_ids = fixtures.create("subscribers", subscriber_inputs)
    manifest = [{**item, "id": identifier} for identifier, item in zip(content_ids, content_inputs)]
    expected_items = base_items + manifest

    def publication_order(item):
        return item["published_at"] is not None, item["published_at"] or "", item["id"]

    published_items = sorted(
        [item for item in expected_items if item["status"] == "published"],
        key=publication_order,
        reverse=True,
    )
    published = [item["id"] for item in published_items]
    draft = [
        item["id"]
        for item in sorted(
            [item for item in expected_items if item["status"] == "draft"],
            key=lambda item: (item["updated_at"], item["id"]),
            reverse=True,
        )
    ]
    filtered = [item["id"] for item in published_items if item["category"] == "Getting started"]
    searched = [
        item["id"]
        for item in sorted(manifest, key=publication_order, reverse=True)
        if item["status"] == "published" and item["category"] == "Getting started"
    ]
    categories = sorted([row["id"] for row in base_categories] + category_ids)
    subscribers = sorted([row["id"] for row in base_subscribers] + subscriber_ids, reverse=True)
    category_counts = Counter(item["category"] for item in expected_items)

    try:
        clear_content(cache_folder)
        walk(public, "/content", "items", 12, published)
        walk(public, "/content?category=Getting%20started", "items", 12, filtered)
        walk(public, "/content?q=BODYONLYSCALE&category=Getting%20started", "items", 12, searched)
        walk(admin, "/admin/content?status=draft", "items", 20, draft)
        walk(admin, "/admin/categories", "categoryList", 20, categories, category_counts)
        walk(admin, "/admin/subscribers", "rows", 30, subscribers, group="pluginPage")
        check(
            page(public, "/content?q=BODYONLYSCALE")["pagination"]["total"] == 83,
            "body search did not run in the database",
        )
        check(
            page(public, "/content?q=literal_%25")["pagination"]["total"] == 1,
            "LIKE wildcards were not escaped",
        )
        check(
            page(public, "/content?q=literal_%25%20%21")["pagination"]["total"] == 1,
            "LIKE escape character was not escaped",
        )
        check(
            page(public, "/content?q=BODYONLYSCALE&category=Getting%20started")["pagination"][
                "total"
            ]
            == 17,
            "grouped search escaped the status/category constraints",
        )
        check(
            page(admin, "/admin/content?q=Scale%20fixture&status=draft")["pagination"]["total"]
            == 37,
            "admin search escaped the draft constraint",
        )
        check(
            page(public, "/content?q=%27%20OR%201%3D1--")["pagination"]["total"] == 0,
            "search values became executable statements",
        )
        options_status, _, options_body = public.request(
            "/categories/options?q=Scale%20category%2008"
        )
        options = json.loads(options_body)["categories"]
        check(
            options_status == 200 and "Scale category 086" in options and len(options) <= 20,
            "remote category options were truncated globally",
        )
        nav = page(public, "/")["categories"]
        check(len(nav) <= 12, "global category navigation is unbounded")
        recent = page(admin, "/admin")["items"]
        check(len(recent) == 5, "dashboard fetched more recent content than needed")
        for key, file in content_entries(cache_folder).items():
            if key.split(":")[6] not in {"published-by-slug", "editor-by-id"}:
                check(
                    b"BODYONLYSCALE" not in file.read_bytes(),
                    "a listing cache contains content item bodies",
                )
        print(
            "PASS Larger ORM fixtures: independent expected ordering/counts, forward/back cursors, tied/null dates and body-free caches",
            flush=True,
        )

        clear_content(cache_folder)
        body_paths = {
            "/content/welcome-to-haxepress": 1,
            "/admin/content/1/edit": 1,
        }
        try:
            with fixtures.guard(bodyPaths=body_paths):
                check(
                    public.request("/content/scale-fixture-1")[0] == 500,
                    "content item body guard is inactive",
                )
                check(len(page(public, "/")["items"]) <= 6, "home read content item bodies")
                check(len(page(public, "/content")["items"]) == 12, "site read content item bodies")
                check(
                    len(page(admin, "/admin/content")["items"]) == 20,
                    "admin list read content item bodies",
                )
                check(
                    len(page(admin, "/admin")["items"]) == 5, "dashboard read content item bodies"
                )
                check(
                    len(page(admin, "/admin/categories")["categoryList"]) == 20,
                    "category counts read content item bodies",
                )
                check(public.request("/rss.xml")[0] == 200, "RSS read content item bodies")
                detail = page(public, "/content/welcome-to-haxepress")["item"]
                check(detail["id"] == 1 and bool(detail["content"]), "detail read another body")
                check(
                    page(admin, "/admin/content/1/edit")["item"]["id"] == 1,
                    "editor read another body",
                )
        finally:
            clear_content(cache_folder)
        print(
            "PASS Native result-set guard: cold lists/counts/RSS omit content; details/editors read only their requested row",
            flush=True,
        )

        status, _, body = admin.request("/admin/subscribers/export")
        rows = list(csv.reader(io.StringIO(body)))
        check(
            status == 200 and len(rows) == len(subscribers) + 1, "batched CSV export is incomplete"
        )
        check(len({row[0] for row in rows[1:]}) == len(subscribers), "CSV batching duplicated rows")
        print("PASS Full CSV download uses bounded database batches and a file stream", flush=True)
    finally:
        fixtures.delete("items", [("id", "in", content_ids)])
        fixtures.delete("categories", [("id", "in", category_ids)])
        fixtures.delete("subscribers", [("id", "in", subscriber_ids)])
        clear_content(cache_folder)
    print("All specific-query and bounded-data checks passed.", flush=True)


if __name__ == "__main__":
    run()
