"""Verify optional developer-defined theme controls and the existing native save flow."""

import json
import os
import secrets

from cms_content import HEADERS, props
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore
from validation import post_json


def run():
    owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    public = Client()
    with FixtureStore.from_environment() as fixtures:
        verify(owner, public, fixtures)
    owner.request("/admin/logout", "POST", {})


def verify(owner, public, fixtures):
    identifier = "theme-simple"
    url = f"/admin/themes/{identifier}"
    before = fixtures.rows("cms_packages", ["settings"], [("id", "=", identifier)], limit=1)[0][
        "settings"
    ]
    preview = props(owner, f"{url}/preview")["preview"]
    controls = preview["customization"]
    check(controls and len(controls["session"]) == 32, "Theme customization session is missing")
    fields = {field["key"]: field for field in controls["fields"]}
    check(
        fields["button_color"]["kind"] == "color" and not fields["button_color"]["required"],
        "Button color is not developer-defined and optional",
    )
    check(
        controls["values"]["button_color"] == "", "An unset optional color lost its inherited value"
    )
    frame = props(owner, preview["url"])
    check(
        frame["theme"]["customizeSession"] == controls["session"],
        "Customization context did not reach the frame",
    )
    check(
        "customizeSession" not in props(public, "/")["theme"],
        "Public theme leaked its customization context",
    )
    check(
        fixtures.rows("cms_packages", ["settings"], [("id", "=", identifier)], limit=1)[0][
            "settings"
        ]
        == before,
        "Opening customization persisted settings",
    )
    check(
        owner.request(
            f"{url}/settings", "POST", {**controls["values"], "_context": "preview"}, csrf=False
        )[0]
        == 419,
        "Customization save bypassed CSRF",
    )
    current = controls["values"]
    try:
        changed = {
            **current,
            "button_color": "#b4435f",
            "button_text_color": "#ffffff",
            "_context": "preview",
        }
        status, headers, body = owner.request(f"{url}/settings", "POST", changed)
        check(
            status == 303 and headers["location"] == f"{url}/preview?notice=saved",
            f"Customization save left the preview: {body[:120]}",
        )
        stored = json.loads(
            fixtures.rows("cms_packages", ["settings"], [("id", "=", identifier)], limit=1)[0][
                "settings"
            ]
        )
        check(stored["button_color"] == "#b4435f", "Customization values did not persist")
        check(
            props(public, "/")["theme"]["settings"]["button_color"] == "#b4435f",
            "Saved active-theme values did not invalidate the public cache",
        )
        saved = fixtures.rows("cms_packages", ["settings"], [("id", "=", identifier)], limit=1)[0][
            "settings"
        ]
        status, _, _ = owner.request(
            f"{url}/settings",
            "POST",
            {**changed, "button_color": "url(https://example.test/unsafe)"},
        )
        check(status == 422, "Invalid customization color was accepted")
        check(
            fixtures.rows("cms_packages", ["settings"], [("id", "=", identifier)], limit=1)[0][
                "settings"
            ]
            == saved,
            "Rejected customization changed stored values",
        )
        status, headers, _ = post_json(owner, f"{url}/settings", {**changed, "width": []}, HEADERS)
        check(
            status == 303 and headers["location"] == f"{url}/preview",
            "Native validation lost the preview error context",
        )
        check(
            props(owner, f"{url}/preview")["errors"].get("package"),
            "Native preview error flash was lost",
        )
        check(
            owner.request(f"{url}/settings", "POST", {**changed, "button_color": ""})[0] == 303,
            "Optional custom color could not be cleared",
        )
        check(
            json.loads(
                fixtures.rows("cms_packages", ["settings"], [("id", "=", identifier)], limit=1)[0][
                    "settings"
                ]
            )["button_color"]
            == "",
            "Clearing an optional color restored a forced default",
        )
    finally:
        owner.request(f"{url}/settings", "POST", {**current, "_context": "preview"})

    synthetic = []
    base = fixtures.rows("cms_packages", ["manifest"], [("id", "=", identifier)], limit=1)[0]
    for name, declared in [
        ("no-controls", []),
        (
            "private-controls",
            [{"key": "private_key", "label": "Private setting", "kind": "secret"}],
        ),
    ]:
        suffix = secrets.token_hex(4)
        package_id = f"theme-{name}-{suffix}"
        manifest = {
            **json.loads(base["manifest"]),
            "slug": f"{name}-{suffix}",
            "name": name,
            "fields": declared,
        }
        fixtures.create(
            "cms_packages",
            [
                {
                    "id": package_id,
                    "kind": "theme",
                    "slug": manifest["slug"],
                    "name": name,
                    "name_key": f"{name}{suffix}",
                    "description": "",
                    "author": "",
                    "version": "2.16.0",
                    "directory": "",
                    "manifest": json.dumps(manifest),
                    "settings": "{}",
                    "enabled": 0,
                    "setting_count": len(declared),
                    "last_error": "",
                    "restart_required": 0,
                    "installed_at": "2026-11-05",
                    "updated_at": "2026-11-05",
                }
            ],
        )
        synthetic.append(package_id)
        page = props(owner, f"/admin/themes/{package_id}/preview")["preview"]
        check(
            page["customization"] is None and "customizeSession" not in page["url"],
            "A theme without public fields exposed customization controls",
        )
    for package_id in synthetic:
        fixtures.delete("cms_packages", [("id", "=", package_id)])
    check(public.request(f"{url}/preview")[0] == 303, "Theme customization bypassed admin access")
    print(
        "PASS Theme customization: optional developer fields, secret exclusion, transient preview context, native validation/CSRF, persistence, cache invalidation and inherited colors",
        flush=True,
    )


if __name__ == "__main__":
    run()
