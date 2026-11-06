"""Delete protection across core references, real plugins and unavailable dependency sources."""

import json
import os
from pathlib import Path
import secrets
import sys

from e2e import Client, check
from cms_content import props
from cms_packages import install
from cms_management import login
from fixture_store import FixtureStore, TEST_BINARY

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_packages import build_plugin


def run():
    owner = Client()
    owner.request("/admin/login")
    check(
        owner.request(
            "/admin/login",
            "POST",
            {
                "email": os.environ["TEST_ADMIN_EMAIL"],
                "password": os.environ["TEST_ADMIN_PASSWORD"],
            },
        )[0]
        == 303,
        "Media protection login",
    )
    original_bytes = (ROOT / "public/images/coast.jpg").read_bytes()
    public = Client()

    def references(image, client=owner):
        path = f"/admin/media/{str(image['id'])}/references"
        items = []
        seen = set()
        while path:
            check(path not in seen, "Reference pagination repeated a cursor")
            seen.add(path)
            status, headers, body = client.request(path)
            check(status == 200, f"Reference list: {str(status)} {body[:200]}")
            check(
                headers.get("cache-control") == "private, no-store",
                "Reference details were cacheable",
            )
            page = json.loads(body)
            check(len(page["items"]) <= 20, "Reference page is unbounded")
            items.extend(page["items"])
            path = page["next"]
            check(len(seen) < 20, "Unexpected reference page count")
        check(
            len({item["id"] for item in items}) == len(items),
            "Reference cursors duplicated records",
        )
        return items, page

    def library_state(image):
        page = props(owner, f"/admin/media?q={image['filename']}")
        return next(item for item in page["images"] if item["id"] == image["id"])

    def upload():
        status, _, body = owner.upload_image(
            "/admin/media/upload", original_bytes, "image/jpeg", (1000, 750)
        )
        check(status == 201, "Dependency fixture upload")
        return json.loads(body)

    def blocked(image):
        state = library_state(image)
        check(state["can_delete"] is False, "Referenced image had an enabled delete control")
        locations, report = references(image)
        check(report["canDelete"] is False, "Reference details authorized deleting an in-use image")
        check(locations or not report["verified"], "The report did not explain the deletion lock")
        before = fixtures.rows("media_assets", ["id", "filename"], [("id", "=", image["id"])])
        status, _, body = owner.request(f"/admin/media/{str(image['id'])}/delete", "POST", {})
        check(status == 422, f"Referenced media deletion returned {str(status)}: {body[:200]}")
        check(
            fixtures.rows("media_assets", ["id", "filename"], [("id", "=", image["id"])]) == before,
            "Blocked deletion changed the catalog",
        )
        check(
            public.request(image["url"], binary=True)[2] == original_bytes,
            "Blocked deletion moved or changed the file",
        )

    def unused(image):
        check(
            library_state(image)["can_delete"] is True,
            "Unused image remained locked in the library",
        )
        locations, report = references(image)
        check(
            not locations and report["canDelete"] and report["verified"],
            "Unused reference report was incorrect",
        )
        status, _, body = owner.request(f"/admin/media/{str(image['id'])}/delete", "POST", {})
        check(status == 303, f"Unused media could not be deleted: {str(status)} {body[:300]}")
        check(public.request(image["url"])[0] == 404, "Deleted media file is still served")

    package = build_plugin(
        ROOT / "tests/plugins/media",
        ROOT / "Export/packages",
        ROOT / "Export/packages/cms-plugin-api-4.info",
        TEST_BINARY,
    ).read_bytes()
    with FixtureStore.from_environment() as fixtures:
        image = upload()
        suffix = secrets.token_hex(5)
        content_id = fixtures.create(
            "items",
            [
                {
                    "title": f"Dependency {suffix}",
                    "slug": f"dependency-{suffix}",
                    "excerpt": "A reference in a text field",
                    "content": "An ordinary content body.",
                    "category": "",
                    "image": "",
                    "image_alt": "",
                    "status": "trash",
                    "content_type": "entry",
                    "created_at": "2026-11-04",
                    "updated_at": "2026-11-04",
                }
            ],
        )[0]
        cases = [
            (
                "items",
                {"excerpt": f"Download https://example.test{image['url']}?size=large"},
                [("id", "=", content_id)],
            ),
            (
                "items",
                {"content": f"[An attachment]({image['url']}#photo)"},
                [("id", "=", content_id)],
            ),
        ]
        for entity, values, where in cases:
            original = fixtures.rows(entity, ["id", *values.keys()], where)[0]
            fixtures.update(entity, values, where)
            blocked(image)
            fixtures.update(entity, {key: original[key] for key in values}, where)
        value_id = fixtures.create(
            "content_values",
            [
                {
                    "content_id": content_id,
                    "field_key": "nested_gallery",
                    "value": json.dumps({"nested": [{"source": image["url"]}]}).replace("/", "\\/"),
                    "value_text": "unrelated projection",
                    "value_number": 0,
                }
            ],
        )[0]
        blocked(image)
        fixtures.delete("content_values", [("id", "=", value_id)])
        setting = f"dependency-{suffix}"
        fixtures.create("settings", [{"key": setting, "value": image["url"]}])
        blocked(image)
        fixtures.delete("settings", [("key", "=", setting)])
        fixtures.delete("items", [("id", "=", content_id)])
        unused(image)
        paged = upload()
        owner_id = props(owner, "/admin")["auth"]["admin"]["id"]
        related = fixtures.create(
            "items",
            [
                {
                    "title": f"Private media reference {str(index)}",
                    "slug": f"private-media-{suffix}-{str(index)}",
                    "content": f"![Image]({paged['url']})",
                    "excerpt": "",
                    "category": "",
                    "image": "",
                    "image_alt": "",
                    "status": "draft",
                    "content_type": "entry",
                    "author_id": owner_id,
                    "created_at": "2026-11-04",
                    "updated_at": "2026-11-04",
                }
                for index in range(45)
            ],
        )
        locations, report = references(paged)
        content_locations = [item for item in locations if item["type"] == "Content"]
        check(len(content_locations) == 45, "Multi-page references lost related content")
        check(
            all(item["href"].endswith("/edit") for item in content_locations),
            "Content references did not link to the editor",
        )
        email = f"media-viewer-{suffix}@example.test"
        password = secrets.token_urlsafe(18)
        check(
            owner.request(
                "/admin/team/save",
                "POST",
                {
                    "name": "Media viewer",
                    "email": email,
                    "password": password,
                    "role": "writer",
                    "active": "1",
                },
            )[0]
            == 303,
            "Create restricted media viewer",
        )
        viewer = login(email, password)
        hidden, _ = references(paged, viewer)
        check(
            all(item["restricted"] and item["href"] is None for item in hidden),
            "Private references leaked editor links",
        )
        check(
            "Private media reference" not in json.dumps(hidden), "Private reference titles leaked"
        )
        viewer.request("/admin/logout", "POST", {})
        fixtures.delete("admins", [("email", "=", email)])
        fixtures.delete("items", [("id", "in", related)])
        unused(paged)
        install(owner, "plugins", package)
        check(
            owner.request("/admin/plugins/plugin-media-test/enable", "POST", {})[0] == 303,
            "Enable media dependency plugin",
        )
        registered = upload()
        check(
            owner.request(
                "/admin/media-test",
                "POST",
                {"action": "attach", "key": "registered", "media_id": str(registered["id"])},
            )[0]
            == 200,
            "Plugin retained an ID",
        )
        blocked(registered)
        check(
            owner.request("/admin/plugins/plugin-media-test/disable", "POST", {})[0] == 303,
            "Disable media plugin",
        )
        blocked(registered)
        check(
            owner.request("/admin/plugins/plugin-media-test/uninstall", "POST", {})[0] == 303,
            "Uninstall media plugin",
        )
        blocked(registered)
        install(owner, "plugins", package)
        owner.request("/admin/plugins/plugin-media-test/enable", "POST", {})
        owner.request("/admin/media-test", "POST", {"action": "detach", "key": "registered"})
        unused(registered)
        watched = upload()
        check(
            owner.request(
                "/admin/media-test",
                "POST",
                {"action": "watch-only", "key": "watched", "media_id": str(watched["id"])},
            )[0]
            == 200,
            "Plugin model reference",
        )
        blocked(watched)
        owner.request("/admin/plugins/plugin-media-test/disable", "POST", {})
        blocked(watched)
        owner.request("/admin/plugins/plugin-media-test/enable", "POST", {})
        owner.request("/admin/media-test", "POST", {"action": "detach", "key": "watched"})
        unused(watched)
        nested = upload()
        check(
            owner.request(
                "/admin/media-test",
                "POST",
                {"action": "json", "key": "nested", "url": f"{nested['url']}?download=1"},
            )[0]
            == 200,
            "Plugin nested JSON reference",
        )
        blocked(nested)
        owner.request("/admin/plugins/plugin-media-test/disable", "POST", {})
        blocked(nested)
        owner.request("/admin/plugins/plugin-media-test/enable", "POST", {})
        owner.request("/admin/media-test", "POST", {"action": "detach", "key": "nested"})
        unused(nested)
        encrypted = upload()
        check(
            owner.request(
                "/admin/plugins/plugin-media-test/settings",
                "POST",
                {"private_asset": encrypted["url"]},
            )[0]
            == 303,
            "Private package media setting",
        )
        stored = fixtures.rows(
            "cms_packages", ["id", "settings"], [("id", "=", "plugin-media-test")]
        )[0]
        check(
            Path(encrypted["url"]).name not in stored["settings"],
            "Private media setting was stored in plaintext",
        )
        blocked(encrypted)
        owner.request("/admin/plugins/plugin-media-test/disable", "POST", {})
        blocked(encrypted)
        owner.request("/admin/plugins/plugin-media-test/enable", "POST", {})
        check(
            owner.request(
                "/admin/plugins/plugin-media-test/settings",
                "POST",
                {"private_asset": "", "clear_private_asset": "1"},
            )[0]
            == 303,
            "Clear removed private media reference",
        )
        unused(encrypted)
        candidate = upload()
        source = fixtures.rows(
            "media_dependency_sources",
            ["key", "column_name", "connection_name"],
            [("owner", "=", "plugin-media-test")],
        )[0]
        fixtures.update(
            "media_dependency_sources",
            {"column_name": "missing_media_column"},
            [("key", "=", source["key"])],
        )
        blocked(candidate)
        fixtures.update(
            "media_dependency_sources",
            {"column_name": source["column_name"], "connection_name": "missing_connection"},
            [("key", "=", source["key"])],
        )
        blocked(candidate)
        fixtures.update(
            "media_dependency_sources",
            {"connection_name": source["connection_name"]},
            [("key", "=", source["key"])],
        )
        unused(candidate)
        owner.request("/admin/plugins/plugin-media-test/disable", "POST", {})
        owner.request("/admin/plugins/plugin-media-test/uninstall", "POST", {})
        owner.request("/admin/logout", "POST", {})
    print(
        "PASS Media deletion: nested/escaped/core text references, persistent plugin IDs, disabled/uninstalled owner data, watched models, fail-closed checks and unchanged blocked files",
        flush=True,
    )


if __name__ == "__main__":
    run()
