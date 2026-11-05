"""Verify ORM migrations across multiple batches while preserving existing content."""

import json
from pathlib import Path
from fixture_store import CONTENT_COLUMNS


def prepare(fixtures):
    fixtures.update("settings", {"value": "Current publisher"}, [("key", "=", "publisher_name")])
    fixtures.delete("settings", [("key", "=", "about_site")])
    fixtures.create(
        "settings",
        [
            {"key": "author_name", "value": "Legacy publisher"},
            {"key": "author_bio", "value": "Preserved site introduction"},
        ],
    )
    stamp = "2026-11-03 12:00:00"
    contents = ["", "word " * 199, "word " * 200, "a  b", "word " * 600]
    inputs = [
        {
            "title": "Migration fixture " + str(index),
            "slug": "migration-fixture-" + str(index),
            "excerpt": "",
            "content": contents[index % len(contents)],
            "category": "Migration category " + str(index % 105).zfill(3),
            "image": "",
            "image_alt": "",
            "status": "draft",
            "featured": 0,
            "reading_minutes": 99 if index % 17 == 0 else 0,
            "published_at": None,
            "created_at": stamp,
            "updated_at": stamp,
        }
        for index in range(205)
    ]
    fixtures.create("items", inputs)
    fixtures.update("items", {"reading_minutes": 0}, [("id", "in", [1, 2, 3])])
    fixtures.call("drop_categories")
    fixtures.delete("settings", [("key", "in", ["query_metadata_v1", "managed_categories_v1"])])
    records = list(fixtures.scan("items", CONTENT_COLUMNS))
    for record in records:
        if record["reading_minutes"] == 0:
            record["reading_minutes"] = max(1, (record["content"].count(" ") + 200) // 200)

    seed_file = Path(__file__).resolve().parents[1] / "database/seed.json"
    seeds = json.loads(seed_file.read_text())
    category_names = {
        " ".join(record["category"].split()) for record in records + seeds if record["category"]
    }
    return records, category_names


def verify(fixtures, expected):
    identity = fixtures.rows(
        "settings",
        ["key", "value"],
        [("key", "in", ["publisher_name", "about_site", "author_name", "author_bio"])],
        limit=4,
    )
    if {row["key"]: row["value"] for row in identity} != {
        "publisher_name": "Current publisher",
        "about_site": "Preserved site introduction",
    }:
        raise AssertionError(
            "Site identity migration lost legacy values or overwrote current settings."
        )
    records, category_names = expected
    actual = list(fixtures.scan("items", CONTENT_COLUMNS))
    if actual != records:
        raise AssertionError(
            "Batched reading-time migration lost rows, changed content/dates, or overwrote metadata."
        )
    names = {row["name"] for row in fixtures.scan("categories", ["id", "name"])}
    if names != category_names:
        raise AssertionError("Distinct category migration lost or duplicated category names.")
    for marker in ("query_metadata_v1", "managed_categories_v1"):
        values = fixtures.rows("settings", ["key", "value"], [("key", "=", marker)], limit=1)
        if not values or values[0]["value"] != "1":
            raise AssertionError("Migration completion marker is missing: " + marker)
