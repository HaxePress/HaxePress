"""Verify the built-in theme independently of ZIP availability or current activation."""

import io
import json
import os
import secrets
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

from cms_packages import install, props
from e2e import Client, check
from fixture_store import FixtureStore

ROOT = Path(__file__).resolve().parents[1]


def archive(manifest, css=None):
    data = io.BytesIO()
    with ZipFile(data, "w", compression=ZIP_DEFLATED) as package:
        package.writestr("cms-package.json", json.dumps(manifest))
        for filename in manifest.get("translations", {}).values():
            package.writestr(filename, (ROOT / "resources/themes/simple" / filename).read_bytes())
        if css is not None:
            package.writestr("public/theme.css", css)
    return data.getvalue()


def verify_order(admin, fixtures, source, active_theme):
    suffix = secrets.token_hex(5)
    identifiers = [f"theme-a-pinned-{suffix}-{str(index).zfill(2)}" for index in range(25)]
    records = []
    for index, identifier in enumerate(identifiers):
        name = f"Simple ordering sample {suffix} {str(index)}"
        manifest = {**source, "slug": identifier[6:], "name": name, "translations": {}}
        records.append(
            {
                "id": identifier,
                "kind": "theme",
                "slug": manifest["slug"],
                "name": name,
                "name_key": name.lower(),
                "version": manifest["version"],
                "description": "",
                "author": "Ordering test",
                "directory": manifest["slug"],
                "manifest": json.dumps(manifest),
                "enabled": 0,
                "setting_count": 0,
                "settings": "{}",
                "last_error": "",
                "restart_required": 0,
                "installed_at": "2026-01-01 00:00:00",
                "updated_at": "2026-01-01 00:00:00",
            }
        )
    try:
        fixtures.create("cms_packages", records)
        # A native activation invalidates package queries after test-only ORM inserts.
        admin.request(f"/admin/themes/{active_theme}/enable", "POST", {})
        for initial in ("/admin/themes", "/admin/themes?q=Simple"):
            pages = []
            url = initial
            while url:
                check(len(pages) < 5, "Theme cursor pagination did not terminate")
                page = props(admin, url)
                check(len(page["packages"]) <= 12, "Pinned theme exceeded the page size")
                check(
                    [item["id"] for item in props(admin, url)["packages"]]
                    == [item["id"] for item in page["packages"]],
                    "Warm theme cache changed the pinned order",
                )
                pages.append(page)
                url = page["pagination"]["next"]
            all_ids = [item["id"] for page in pages for item in page["packages"]]
            check(all_ids[0] == "theme-simple", "Default theme was not first while inactive")
            check(all_ids.count("theme-simple") == 1, "Default theme repeated across cursor pages")
            check(len(all_ids) == len(set(all_ids)), "Cursor pages repeated a theme")
            check(set(identifiers).issubset(all_ids), "Pinned pagination skipped an ordinary theme")
            check(all_ids[1:] == sorted(all_ids[1:]), "Ordinary theme SQL order changed")
            for index in range(len(pages) - 1, 0, -1):
                previous = props(admin, pages[index]["pagination"]["previous"])
                check(
                    [item["id"] for item in previous["packages"]]
                    == [item["id"] for item in pages[index - 1]["packages"]],
                    "Reverse cursor did not restore the pinned first page",
                )
        check(
            all(
                item["id"] != "theme-simple"
                for item in props(admin, "/admin/themes?q=Fieldnotes")["packages"]
            ),
            "Default theme ignored the search filter",
        )
    finally:
        for identifier in identifiers:
            fixtures.delete("cms_packages", [("id", "=", identifier)])
        admin.request(f"/admin/themes/{active_theme}/enable", "POST", {})


def run():
    admin = Client()
    public = Client()
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
        "Built-in theme login",
    )
    default = "theme-simple"
    original_theme = props(public, "/")["theme"]["id"]
    original_settings = props(admin, f"/admin/themes/{default}/settings")["values"]
    source = json.loads((ROOT / "resources/themes/simple/cms-package.json").read_text())
    custom = {
        **source,
        "slug": "built-in-probe",
        "name": "Temporary theme",
        "assets": {"stylesheet": "theme.css"},
        "translations": {},
    }
    identifier = None
    try:
        with FixtureStore.from_environment() as fixtures:
            stored = fixtures.rows("cms_packages", ["directory"], [("id", "=", default)])[0]
            check(stored["directory"] == "", "Default theme depends on an installed ZIP directory")
            row = next(
                item for item in props(admin, "/admin/themes")["packages"] if item["id"] == default
            )
            check(row["built_in"] is True, "Default theme was not marked as built in")
            install(admin, "themes", archive(custom, ".simple-site {--green:#325697;}"))
            identifier = f"theme-{custom['slug']}"
            check(
                admin.request(f"/admin/themes/{identifier}/enable", "POST", {})[0] == 303,
                "Activate a different theme",
            )
            before = fixtures.rows(
                "cms_packages",
                ["id", "enabled", "directory", "manifest", "settings"],
                [("id", "=", default)],
            )
            check(
                before[0]["enabled"] == 0, "Default theme was not inactive during protection test"
            )
            verify_order(admin, fixtures, source, identifier)
            check(
                admin.request(f"/admin/themes/{default}/uninstall", "POST", {})[0] == 422,
                "Inactive default theme could be uninstalled",
            )
            replacement = admin.request(
                "/admin/themes/upload",
                "POST",
                raw=archive(source),
                content_type="application/zip",
            )
            check(
                replacement[0] == 422 and "built-in" in replacement[2],
                "A ZIP could overwrite the default theme",
            )
            after = fixtures.rows(
                "cms_packages",
                ["id", "enabled", "directory", "manifest", "settings"],
                [("id", "=", default)],
            )
            check(after == before, "Rejected operations changed the default theme")
            values = {**original_settings, "accent": "#2569a3", "width": "800"}
            check(
                admin.request(f"/admin/themes/{default}/settings", "POST", values)[0] == 303,
                "Built-in customization failed",
            )
            preview = props(admin, f"/admin/themes/{default}/preview/frame")["theme"]
            check(
                preview["built_in"] and preview["stylesheet"] == "" and preview["renderer"] == "",
                "Built-in preview still needs package assets",
            )
            check(
                preview["settings"]["accent"] == "#2569a3"
                and preview["settings"]["width"] == "800",
                "Built-in preview ignored saved settings",
            )
            check(
                admin.request(f"/admin/themes/{default}/enable", "POST", {})[0] == 303,
                "Built-in theme could not be activated",
            )
            check(
                props(public, "/")["theme"]["built_in"] is True,
                "Built-in activation did not reach the site",
            )
            messages = props(public, "/?lang=tr")["i18n"]["catalogues"][default]
            check(messages["Simple"] == "Sade", "Built-in public translations need package files")
            check(
                'aria-label="Uninstall Simple"' not in admin.request("/admin/themes")[2],
                "The panel offered default theme deletion",
            )
    finally:
        admin.request(f"/admin/themes/{default}/settings", "POST", original_settings)
        admin.request(f"/admin/themes/{original_theme}/enable", "POST", {})
        if identifier:
            admin.request(f"/admin/themes/{identifier}/uninstall", "POST", {})
        admin.request("/admin/logout", "POST", {})
    print(
        "PASS Built-in theme: package-free registration, inactive uninstall/ZIP replacement protection, customization, preview and activation",
        flush=True,
    )


if __name__ == "__main__":
    run()
