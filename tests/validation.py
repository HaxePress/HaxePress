"""Exercise native validation and endpoint-specific failure responses over real HTTP."""

import json
import os
from pathlib import Path
import secrets

from cms_content import HEADERS, props
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore

ROOT = Path(__file__).resolve().parents[1]


def post_json(client, path, values, headers=None):
    return client.request(
        path,
        "POST",
        raw=json.dumps(values).encode(),
        content_type="application/json",
        extra_headers=headers,
    )


def run():
    owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    public = Client()
    with FixtureStore.from_environment() as fixtures:
        verify(owner, public, fixtures)


def verify(owner, public, fixtures):
    owner_id = props(owner, "/admin")["auth"]["admin"]["id"]
    owner_before = fixtures.rows("admins", ["name", "password"], [("id", "=", owner_id)], limit=1)
    package_before = fixtures.rows(
        "cms_packages", ["settings"], [("id", "=", "plugin-newsletter")], limit=1
    )
    settings_before = fixtures.rows("settings", ["value"], [("key", "=", "site_name")], limit=1)
    image_response = owner.upload_image(
        "/admin/media/upload",
        (ROOT / "public/images/coast.jpg").read_bytes(),
        "image/jpeg",
        (1000, 750),
    )
    check(image_response[0] == 201, "Validation fixture image upload")
    image_id = json.loads(image_response[2])["id"]
    media_path = f"/admin/media/{str(image_id)}/save"
    media_before = fixtures.rows("media_assets", ["title", "alt"], [("id", "=", image_id)], limit=1)
    entities = [
        "items",
        "categories",
        "tags",
        "menu_links",
        "admins",
        "editor_drafts",
        "subscribers",
    ]
    counts_before = {entity: fixtures.count(entity) for entity in entities}
    cases = [
        ("/admin/content/save", {"title": ["invalid"], "slug": "validation", "status": "draft"}),
        ("/admin/pages/save", {"title": "x" * 181, "slug": "validation", "status": "draft"}),
        ("/admin/collections/entry/save", {"title": "Validation", "slug": [], "status": "draft"}),
        ("/admin/categories/save", {"name": ["invalid"]}),
        ("/admin/categories/save", {"name": "x" * 201}),
        ("/admin/tags/save", {"name": "Validation", "slug": [], "description": ""}),
        ("/admin/tags/save", {"name": "x" * 81, "slug": "validation"}),
        (media_path, {"title": [], "alt": ""}),
        (media_path, {"title": "Validation", "alt": "x" * 501}),
        (
            "/admin/navigation/save",
            {"label": [], "url": "/", "location": "header", "position": "0"},
        ),
        ("/admin/navigation/save", {"label": "Validation", "url": "x" * 1001}),
        ("/admin/team/save", {"name": "Validation", "email": [], "role": "writer"}),
        (
            "/admin/team/save",
            {"name": "Validation", "email": "test@example.test", "role": "writer", "password": []},
        ),
        ("/admin/account", {"name": []}),
        ("/admin/account", {"name": "x" * 101}),
        ("/admin/settings", {"site_name": []}),
        ("/admin/settings", {"site_name": "Validation", "description": "x" * 501}),
        ("/admin/plugins/plugin-newsletter/settings", {"title": []}),
        ("/admin/plugins/plugin-newsletter/settings", {"title": "x" * 2001}),
        ("/admin/themes/theme-simple/settings", {"accent": []}),
    ]
    try:
        for path, values in cases:
            status, _, body = post_json(owner, path, values)
            check(
                status == 422,
                f"{path} did not reject invalid fields: {str(status)} {body[:120]}",
            )
        for path in [
            "/admin/content/working-copy",
            "/admin/pages/working-copy",
            "/admin/collections/entry/working-copy",
        ]:
            for invalid in ({"content": ["invalid"]}, {"content": "x" * 100001}):
                status, headers, body = post_json(owner, path, invalid)
                check(
                    status == 422
                    and "application/json" in headers["content-type"]
                    and json.loads(body)["error"] == "The working copy exceeds the editor limits.",
                    "Working-copy native failure response changed",
                )
        for values in (
            {
                "current_password": [],
                "new_password": "valid-password",
                "confirm_password": "valid-password",
            },
            {
                "current_password": "wrong-current-password",
                "new_password": "ğ" * 37,
                "confirm_password": "ğ" * 37,
            },
            {
                "current_password": "wrong-current-password",
                "new_password": "short",
                "confirm_password": "short",
            },
        ):
            status, _, body = post_json(owner, "/admin/password", values)
            check(
                status == 422 and "between 12 and 72 bytes" in body,
                "Password policy did not run before password verification",
            )
        for current, password, confirmation, message in [
            ("x" * 73, "valid-password", "valid-password", "Your current password is incorrect."),
            ("wrong-current-password", "ğ" * 36, "ğ" * 36, "Your current password is incorrect."),
            (
                os.environ["TEST_ADMIN_PASSWORD"],
                "valid-password",
                "different-password",
                "The new passwords do not match.",
            ),
        ]:
            status, _, body = post_json(
                owner,
                "/admin/password",
                {
                    "current_password": current,
                    "new_password": password,
                    "confirm_password": confirmation,
                },
            )
            check(
                status == 422 and message in body,
                "Existing password checks or the 72-byte boundary changed",
            )

        for path, values in [
            ("/locale", {"locale": []}),
            ("/locale", {"locale": "en", "return_to": []}),
            ("/subscribe", {"email": []}),
            ("/subscribe", {"email": "invalid-email"}),
        ]:
            status, headers, body = post_json(public, path, values)
            check(
                status == 422
                and "application/json" in headers["content-type"]
                and json.loads(body).get("error"),
                "Public native failure lost its JSON response",
            )
            check("set-cookie" not in headers, "Public validation opened a session or set a locale")

        status, headers, _ = post_json(owner, "/admin/account", {"name": []}, HEADERS)
        check(
            status == 303 and headers["location"] == "/admin/account",
            "Inertia validation did not redirect",
        )
        check(
            props(owner, "/admin/account")["errors"].get("account"),
            "Inertia validation lost its scoped flash error",
        )
        check(
            not props(owner, "/admin/account")["errors"],
            "Inertia validation errors were not consumed",
        )
        for path, values in [
            ("/admin/categories/save", {"id": "2147483647", "name": []}),
            ("/admin/tags/save", {"id": "2147483647", "name": []}),
            (
                "/admin/tags/save",
                {
                    "id": "9999999999999999",
                    "name": "Overflow identifier",
                    "slug": "invalid-identifier",
                    "description": [],
                },
            ),
            ("/admin/content/save", {"id": "2147483647", "title": []}),
            ("/admin/plugins/missing-plugin/settings", {"title": []}),
        ]:
            check(
                post_json(owner, path, values)[0] == 404,
                "Missing-resource status precedence changed",
            )
        item = fixtures.rows("items", ["id", "version"], [("content_type", "=", "entry")], limit=1)[
            0
        ]
        conflict = {"id": str(item["id"]), "version": str(item["version"] + 1), "title": []}
        check(
            post_json(owner, "/admin/content/save", conflict)[0] == 409,
            "Stale content lost its conflict response",
        )
        check(
            post_json(owner, "/admin/content/working-copy", conflict)[0] == 409,
            "Stale working copy lost its conflict response",
        )

        check(
            counts_before == {entity: fixtures.count(entity) for entity in entities},
            "Invalid requests wrote application data",
        )
        check(
            owner_before
            == fixtures.rows("admins", ["name", "password"], [("id", "=", owner_id)], limit=1),
            "Invalid account/password input changed credentials",
        )
        check(
            package_before
            == fixtures.rows(
                "cms_packages", ["settings"], [("id", "=", "plugin-newsletter")], limit=1
            ),
            "Invalid package settings were persisted",
        )
        check(
            settings_before
            == fixtures.rows("settings", ["value"], [("key", "=", "site_name")], limit=1),
            "Invalid site settings were persisted",
        )
        check(
            media_before
            == fixtures.rows("media_assets", ["title", "alt"], [("id", "=", image_id)], limit=1),
            "Invalid media metadata was persisted",
        )
        verify_permissions(owner, fixtures)
        owner.request("/admin/plugins/plugin-newsletter/disable", "POST", {})
        check(
            post_json(public, "/subscribe", {"email": []})[0] == 404,
            "An inactive plugin still validated requests",
        )
        owner.request("/admin/plugins/plugin-newsletter/enable", "POST", {})
        check(
            post_json(public, "/subscribe", {"email": []})[0] == 422,
            "Reactivated plugin validation did not return",
        )
    finally:
        owner.request(f"/admin/media/{str(image_id)}/delete", "POST", {})
        owner.request("/admin/logout", "POST", {})
    print(
        "PASS Native validation: all write handlers, plugin forwarding, JSON/Inertia responses, no writes, byte limits, permissions and 404/409 precedence",
        flush=True,
    )


def verify_permissions(owner, fixtures):
    email = f"validation-writer-{secrets.token_hex(5)}@example.test"
    password = secrets.token_urlsafe(18)
    check(
        owner.request(
            "/admin/team/save",
            "POST",
            {
                "name": "Validation writer",
                "email": email,
                "password": password,
                "role": "writer",
                "active": "1",
            },
        )[0]
        == 303,
        "Create validation permission fixture",
    )
    identifier = fixtures.rows("admins", ["id"], [("email", "=", email)], limit=1)[0]["id"]
    writer = login(email, password)
    try:
        for path in [
            "/admin/categories/save",
            "/admin/tags/save",
            "/admin/navigation/save",
            "/admin/team/save",
            "/admin/settings",
            "/admin/plugins/plugin-newsletter/settings",
        ]:
            check(
                post_json(writer, path, {"name": [], "label": [], "site_name": [], "title": []})[0]
                == 403,
                f"Invalid fields bypassed permission precedence: {path}",
            )
    finally:
        writer.request("/admin/logout", "POST", {})
        fixtures.delete("admins", [("id", "=", identifier)])


if __name__ == "__main__":
    run()
