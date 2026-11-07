"""Verify installed plugin/theme behavior through the owner panel and public site."""

import base64
import io
import json
import os
from pathlib import Path
from urllib.parse import urlencode
from uuid import uuid4
import secrets
import shutil
import tempfile
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from build_packages import build_plugin
import zipfile
import re

from e2e import Client, check
from fixture_store import FixtureStore

ROOT = Path(__file__).resolve().parents[1]
HEADERS = {"X-Well-Data": "true", "Accept": "application/json"}
GITHUB_EXAMPLE = "https://github.com/hxwell/haxepress-plugin-example"


def props(client, path):
    status, _, body = client.request(path, extra_headers=HEADERS)
    check(status == 200, f"{path} returned {str(status)}: {body[:200]}")
    return json.loads(body)["props"]


def upload(admin, kind, package):
    status, _, body = admin.request(
        f"/admin/{kind}/upload", "POST", raw=package, content_type="application/zip"
    )
    check(status == 201, f"package inspection returned {str(status)}: {body[:400]}")
    return json.loads(body)


def install(admin, kind, package, replace=False):
    inspected = upload(admin, kind, package)
    status, _, body = admin.request(
        f"/admin/{kind}/install",
        "POST",
        {"key": inspected["key"], "replace": "1" if replace else "0"},
    )
    check(status == 303, f"package install returned {str(status)}: {body[:200]}")
    return inspected


def zip_bytes(manifest, files):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("cms-package.json", json.dumps(manifest))
        for name, content in files.items():
            archive.writestr(name, content)
    return output.getvalue()


def updated_server_modules():
    """Build changed JVM, CPPIA and PHP artifacts from one source revision."""
    example = ROOT / "examples/plugins/reading-companion"
    source_path = "src/example/reading/ReadingPlugin.hx"
    source = (example / source_path).read_text()
    original = "var message:String = input.settings.message;"
    check(original in source, "plugin update fixture no longer matches its source")
    with tempfile.TemporaryDirectory(prefix="cms-plugin-update-") as name:
        work = Path(name)
        plugin = work / "plugin"
        shutil.copytree(example, plugin)
        (plugin / source_path).write_text(
            source.replace(
                original, "var message:String = 'Updated module: ${input.settings.message}';"
            )
        )
        package = build_plugin(plugin, work, ROOT / "Export/packages/cms-plugin-api-4.info")
        with zipfile.ZipFile(package) as archive:
            return {
                path: archive.read(path)
                for path in archive.namelist()
                if path in ("server.jar", "server.cppia") or path.startswith("php/")
            }


def verify_line_breaks(admin, manifest, files):
    """`$` also matches before a final line break, and `trim()` keeps the Unicode separators."""
    for ending in ["\u2028", "\u0085"]:
        variants = []
        for field in ["pluginId", "slug", "version"]:
            variants.append((field, {**manifest, field: f"{manifest[field]}{ending}"}, files))
        setting = json.loads(json.dumps(manifest))
        setting["fields"][0]["key"] = f"{setting['fields'][0]['key']}{ending}"
        variants.append(("setting key", setting, files))
        extra_file = {**files, f"public/extra.js{ending}": "export {};"}
        variants.append(("file name", manifest, extra_file))
        for name, changed, archive_files in variants:
            status, _, body = admin.request(
                "/admin/plugins/upload",
                "POST",
                raw=zip_bytes(changed, archive_files),
                content_type="application/zip",
            )
            check(
                status == 422,
                f"A package {name} ending in {ending!r} was accepted: {str(status)} {body[:200]}",
            )


def run():
    with FixtureStore.from_environment() as fixtures:
        verify(fixtures)


def verify_github_release(admin, public):
    slug = "github-release-example"
    plugin = f"/admin/plugins/plugin-{slug}"
    endpoint = f"/{slug}"
    github = "/admin/plugins/github"
    params = urlencode({"repository": f"{GITHUB_EXAMPLE}/releases", "page": 1})
    status, _, body = admin.request(f"{github}/releases?{params}")
    check(status == 200, f"GitHub release lookup returned {status}: {body[:300]}")
    listing = json.loads(body)
    check(listing["repository"] == GITHUB_EXAMPLE, "The repository URL was not normalized")
    release = next(item for item in listing["releases"] if item["tag"] == "v0.1.1")
    asset = next(item for item in release["assets"] if item["name"] == f"{slug}-0.1.1.zip")
    status, _, body = admin.request(
        f"{github}/inspect", "POST", {"repository": listing["repository"], "asset": asset["id"]}
    )
    check(status == 201, f"GitHub ZIP inspection returned {status}: {body[:300]}")
    inspected = json.loads(body)
    check(inspected["manifest"]["version"] == "0.1.1", "The wrong release ZIP was staged")
    try:
        check(public.request(endpoint)[0] == 404, "ZIP inspection executed the plugin")
        status, _, body = admin.request("/admin/plugins/install", "POST", {"key": inspected["key"]})
        check(status == 303, f"GitHub ZIP installation returned {status}: {body[:300]}")
        check(public.request(endpoint)[0] == 404, "A new installation started automatically")
        check(admin.request(f"{plugin}/enable", "POST", {})[0] == 303, "Plugin activation failed")
        status, _, body = public.request(endpoint)
        check(
            status == 200 and json.loads(body)["status"] == "active",
            "The release module did not run",
        )
    finally:
        admin.request(f"{plugin}/uninstall", "POST", {})
        admin.request("/admin/plugins/discard", "POST", {"key": inspected["key"]})
    check(public.request(endpoint)[0] == 404, "Removing the plugin left its route registered")
    print("PASS Real GitHub release listing, ZIP inspection, install and activation", flush=True)


def verify(fixtures):
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
        "package owner login",
    )
    check(public.request("/admin/plugins")[0] == 303, "plugin panel bypassed the guard")
    check(
        "Install from GitHub" in admin.request("/admin/plugins")[2], "The plugin picker is missing"
    )
    github = "/admin/plugins/github"
    repository = GITHUB_EXAMPLE
    params = urlencode({"repository": repository, "page": 1})
    check(
        public.request(f"{github}/releases?{params}")[0] == 303, "GitHub lookup bypassed the guard"
    )
    check(
        admin.request(
            f"{github}/inspect", "POST", {"repository": repository, "asset": "1"}, csrf=False
        )[0]
        == 419,
        "GitHub package staging bypassed CSRF",
    )
    untrusted = urlencode({"repository": "https://github.com.example.test/owner/plugin", "page": 1})
    check(
        admin.request(f"{github}/releases?{untrusted}")[0] == 422,
        "A lookalike GitHub host was accepted",
    )
    check(
        admin.request(
            f"{github}/inspect",
            "POST",
            {"repository": repository, "asset": "https://example.test/package.zip"},
        )[0]
        == 422,
        "Package staging accepted a direct download URL",
    )
    if os.environ.get("TEST_GITHUB_RELEASE") == "true":
        verify_github_release(admin, public)
    rejected = admin.request("/admin/plugins/upload", "POST", raw=b"invalid", csrf=False)
    check(
        rejected[0] == 419,
        f"package CSRF rejection returned {str(rejected[0])}: {rejected[2][:300]}",
    )
    check(
        admin.request("/admin/plugins/upload", "POST", raw=b"invalid")[0] == 422,
        "invalid ZIP accepted",
    )

    theme_page = props(admin, "/admin/themes")
    initial_preview_revision = theme_page["themePreviewRevision"]
    check(len(initial_preview_revision) == 32, "Theme preview cache revision is missing")
    check(
        {item["slug"] for item in theme_page["packages"]}
        >= {"simple", "fieldnotes", "notebook", "gallery"},
        "bundled themes are missing",
    )
    check(props(public, "/")["theme"]["slug"] == "simple", "default theme is not active")
    for slug in ["simple", "notebook", "gallery", "fieldnotes"]:
        check(
            admin.request(f"/admin/themes/theme-{slug}/enable", "POST", {})[0] == 303,
            f"activate theme {slug}",
        )
        theme = props(public, "/")["theme"]
        check(
            theme["layout"] == slug and (theme["built_in"] or theme["stylesheet"]),
            "theme activation did not affect public props",
        )
        rendered = public.request("/")[2]
        if slug == "simple":
            check(
                "simple-site" in rendered and 'class="hero"' not in rendered,
                "simple theme retained the editorial hero",
            )
        else:
            check(
                'class="featured-content"' in rendered and 'class="hero"' not in rendered,
                "packaged theme did not render its own pages",
            )
            check("renderer" not in theme, "packaged theme still declares a browser renderer")
            check(
                f'<link rel="stylesheet" href="{theme["stylesheet"]}">' in rendered
                and "data-page=" not in rendered,
                "packaged theme pages were not rendered on the server with their stylesheet",
            )
        if not theme["built_in"]:
            status, headers, stylesheet = public.request(theme["stylesheet"])
            check(
                status == 200 and "set-cookie" not in headers and ".cms-site" in stylesheet,
                "theme asset serving",
            )
        else:
            check(
                theme["stylesheet"] == "" and theme["assetBase"] == "",
                "Built-in theme uses package assets",
            )
    cards = admin.request("/admin/themes")[2]
    preview_revision = props(admin, "/admin/themes")["themePreviewRevision"]
    check(
        preview_revision != initial_preview_revision,
        "Theme changes did not invalidate cached preview images",
    )
    check(
        cards.count('class="theme-thumbnail"') == 4
        and cards.count('data-preview-state="loading"') == 4
        and "<iframe" not in cards
        and cards.count(f"snapshot={preview_revision}") == 4
        and "theme-thumbnail-gallery" not in cards,
        "Theme cards did not defer their cached preview captures",
    )
    preview = props(admin, "/admin/themes/theme-gallery/preview")
    content_url = preview["preview"]["url"]
    status, parent_headers, parent_html = admin.request("/admin/themes/theme-gallery/preview")
    check(
        status == 200
        and 'class="theme-preview-banner"' in parent_html
        and "<iframe" in parent_html,
        "preview toolbar and iframe shell",
    )
    check(
        preview.get("theme") is None
        and "/extension-assets/" not in parent_html
        and parent_headers["x-frame-options"] == "DENY",
        "parent preview page loaded theme styles or changed its frame policy",
    )
    status, frame_headers, frame_html = admin.request(content_url)
    content = props(admin, content_url)
    check(
        status == 200
        and content["theme"]["layout"] == "gallery"
        and content["theme"]["previewBase"].endswith("/preview/frame")
        and 'class="featured-content"' in frame_html
        and 'class="theme-preview-banner"' not in frame_html,
        "inactive theme content was not isolated from its toolbar",
    )
    frame_policy = frame_headers["content-security-policy"]
    check(
        frame_headers["x-frame-options"] == "SAMEORIGIN"
        and "frame-ancestors 'self'" in frame_policy
        and "script-src 'self' 'nonce-" in frame_policy,
        f"preview iframe policy: {frame_policy}",
    )
    frame_base = content["theme"]["previewBase"]
    check(
        props(admin, f"{frame_base}/content")["theme"]["id"] == "theme-gallery",
        "site navigation lost preview theme",
    )
    check(
        props(admin, f"{frame_base}/content/welcome-to-haxepress")["theme"]["id"]
        == "theme-gallery",
        "content item navigation lost preview theme",
    )
    check(public.request(frame_base)[0] == 303, "preview iframe bypassed authentication")
    check(
        public.request("/admin/themes/theme-gallery/preview")[0] == 303,
        "preview shell bypassed authentication",
    )
    check(
        f"{frame_base}/content" in frame_html,
        "preview links did not retain their frame route",
    )
    check(props(public, "/")["theme"]["layout"] == "fieldnotes", "preview changed the active theme")
    values = props(admin, "/admin/themes/theme-notebook/settings")["values"]
    values["accent"] = "#234567"
    check(
        admin.request("/admin/themes/theme-notebook/settings", "POST", values)[0] == 303,
        "theme customization",
    )
    check(
        admin.request("/admin/themes/theme-notebook/enable", "POST", {})[0] == 303,
        "activate customized theme",
    )
    check(
        props(public, "/")["theme"]["settings"]["accent"] == "#234567",
        "theme settings did not reach public output",
    )
    check(
        admin.request("/admin/themes/theme-notebook/uninstall", "POST", {})[0] == 422,
        "active theme was removed",
    )
    admin.request("/admin/themes/theme-fieldnotes/enable", "POST", {})

    package = (ROOT / "Export/packages/reading-companion-2.16.0.zip").read_bytes()
    inspected = install(admin, "plugins", package)
    check(inspected["serverTarget"] == "jvm", "JVM package selection")
    check(inspected["manifest"]["serverCppia"] == "server.cppia", "CPPIA artifact metadata")
    check(inspected["manifest"]["serverPhp"] == "php/module.json", "PHP artifact metadata")
    check(
        inspected["manifest"]["entrypoint"] == "example.reading.ReadingPlugin",
        "server package metadata",
    )
    check(
        not any(
            item["content"] == "Integration reading note"
            for item in props(public, "/")["extensions"]["blocks"]
        ),
        "inactive plugin produced public output",
    )
    plugin_id = "plugin-reading-companion"
    check(
        admin.request(
            f"/admin/plugins/{plugin_id}/settings",
            "POST",
            {
                "message": "Integration reading note",
                "content_note": "false",
                "minimum_characters": "0",
            },
        )[0]
        == 303,
        "Configure the reading note",
    )
    check(
        admin.request(f"/admin/plugins/{plugin_id}/enable", "POST", {})[0] == 303,
        "activate JVM plugin",
    )
    blocks = props(public, "/")["extensions"]["blocks"]
    check(
        any(item["slot"] == "dashboard" for item in props(admin, "/admin")["widgets"]),
        "plugin dashboard hook did not run",
    )
    check(
        any(item["content"] == "Integration reading note" for item in blocks),
        "JVM hook did not affect the site",
    )
    message = f"A site note {secrets.token_hex(5)}"
    settings = {"message": message, "content_note": "true", "minimum_characters": "0"}
    check(
        admin.request(f"/admin/plugins/{plugin_id}/settings", "POST", settings)[0] == 303,
        "configure plugin",
    )
    check(message in public.request("/")[2], "plugin output is missing from server-rendered HTML")
    page_data = {
        "id": "",
        "title": "Plugin rendering test",
        "slug": f"plugin-page-{secrets.token_hex(5)}",
        "content": "A published page used to verify content hooks.",
        "status": "published",
        "stay": "1",
    }
    admin.request(
        f"/admin/plugins/{plugin_id}/settings",
        "POST",
        {**settings, "minimum_characters": "1000"},
    )
    rejected = admin.request("/admin/pages/save", "POST", page_data)
    check(
        rejected[0] == 422 and "Reading Companion requires" in rejected[2],
        "content validation hook was ignored",
    )
    admin.request(f"/admin/plugins/{plugin_id}/settings", "POST", settings)
    saved = admin.request("/admin/pages/save", "POST", page_data)
    check(saved[0] == 303, "save plugin render page")
    page_id = int(re.search(r"/pages/(\d+)/edit", saved[1]["location"]).group(1))
    check(
        message in props(public, f"/pages/{page_data['slug']}")["item"]["content"],
        "content render hook was ignored",
    )
    check(
        fixtures.rows("items", ["id", "content"], [("id", "=", page_id)], limit=1)[0]["content"]
        == page_data["content"],
        "a presentation hook mutated stored content",
    )
    check(
        admin.request(f"/admin/plugins/{plugin_id}/disable", "POST", {})[0] == 303,
        "deactivate plugin",
    )
    check(
        not any(item["content"] == message for item in props(public, "/")["extensions"]["blocks"]),
        "disabled plugin kept affecting public output",
    )
    check(
        message not in props(public, f"/pages/{page_data['slug']}")["item"]["content"],
        "disabled plugin still rendered content item content",
    )
    admin.request(f"/admin/pages/{str(page_id)}/delete", "POST", {})
    check(
        admin.request(f"/admin/plugins/{plugin_id}/enable", "POST", {})[0] == 303,
        "reactivate plugin",
    )

    with zipfile.ZipFile(io.BytesIO(package)) as archive:
        manifest = json.loads(archive.read("cms-package.json"))
        package_files = {
            name: archive.read(name) for name in archive.namelist() if name != "cms-package.json"
        }
    manifest["version"] = "2.8.1"
    package_files = {
        path: content for path, content in package_files.items() if not path.startswith("php/")
    }
    package_files.update(updated_server_modules())
    install(admin, "plugins", zip_bytes(manifest, package_files), replace=True)
    current = props(admin, "/admin/plugins")["packages"]
    check(
        next(item for item in current if item["id"] == plugin_id)["version"] == "2.8.1",
        "package update did not persist",
    )
    check(
        any(
            item["content"] == f"Updated module: {message}"
            for item in props(public, "/")["extensions"]["blocks"]
        ),
        "updating a plugin lost settings or active state",
    )

    frontend = {
        "apiVersion": 4,
        "cmsVersion": "2.16.0",
        "kind": "plugin",
        "pluginId": str(uuid4()),
        "slug": "test-banner",
        "name": "Test Banner",
        "version": "2.16.0",
        "description": "A frontend extension test.",
        "author": "CMS tests",
        "assets": {"module": "main.mjs", "stylesheet": "style.css"},
        "fields": [
            {"key": "message", "label": "Message", "kind": "text", "defaultValue": "Hello"},
            {"key": "api_key", "label": "Private API key", "kind": "secret", "required": True},
        ],
    }
    frontend["server"] = manifest["server"]
    frontend_files = {
        **{
            path: content
            for path, content in package_files.items()
            if path in ("server.jar", "server.cppia") or path.startswith("php/")
        },
        "public/main.mjs": "export function activate() { return () => {}; }",
        "public/style.css": ".cms-test-banner { color: green; }",
    }
    frontend_zip = zip_bytes(frontend, frontend_files)
    verify_line_breaks(admin, frontend, frontend_files)
    install(admin, "plugins", frontend_zip)
    frontend_id = "plugin-test-banner"
    check(
        admin.request(f"/admin/plugins/{frontend_id}/enable", "POST", {})[0] == 422,
        "required settings were ignored",
    )
    secret = f"private-{secrets.token_hex(12)}"
    check(
        admin.request(
            f"/admin/plugins/{frontend_id}/settings",
            "POST",
            {"message": "Visible", "api_key": secret},
        )[0]
        == 303,
        "save secret setting",
    )
    secret_page = props(admin, f"/admin/plugins/{frontend_id}/settings")
    check(
        secret_page["values"]["api_key"] == "" and secret_page["secrets"]["api_key"],
        "saved secret leaked into page props",
    )
    stored = fixtures.rows("cms_packages", ["id", "settings"], [("id", "=", frontend_id)], limit=1)[
        0
    ]
    check(secret not in stored["settings"], "secret was stored in plaintext")
    check(
        admin.request(f"/admin/plugins/{frontend_id}/enable", "POST", {})[0] == 303,
        "activate frontend plugin",
    )
    assets = props(public, "/")["extensions"]["assets"]
    asset = next(item for item in assets if item["id"] == frontend_id)
    check(
        "api_key" not in asset["settings"] and secret not in json.dumps(assets),
        "secret leaked to public extension settings",
    )
    status, headers, _ = public.request(asset["module"])
    check(
        status == 200
        and "javascript" in headers.get("content-type", "")
        and "set-cookie" not in headers,
        "module assets are not served statelessly",
    )
    check(
        admin.request(f"/admin/plugins/{frontend_id}/disable", "POST", {})[0] == 303,
        "disable frontend plugin",
    )
    check(public.request(asset["module"])[0] == 404, "disabled plugin assets remain public")
    for identifier in [frontend_id, plugin_id]:
        check(
            admin.request(f"/admin/plugins/{identifier}/uninstall", "POST", {})[0] == 303,
            "uninstall plugin",
        )
        check(
            fixtures.count("cms_packages", [("id", "=", identifier)]) == 0,
            "uninstalled package remained in the database",
        )
        check(
            fixtures.count("package_hooks", [("package_id", "=", identifier)]) == 0,
            "uninstalled package kept hook subscriptions",
        )
    admin.request("/admin/themes/theme-simple/enable", "POST", {})
    print(
        "PASS CMS packages: guarded ZIP install/update, real JVM hooks, frontend assets, encrypted settings, disable/uninstall and theme activation/customization/preview",
        flush=True,
    )


if __name__ == "__main__":
    run()
