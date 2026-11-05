"""Verify visual-theme ZIP round trips, media collisions and download cleanup."""

import copy
import hashlib
import io
import json
import os
from pathlib import Path
import secrets
import socket
import struct
import time
import zipfile
import zlib

from cms_content import props
from cms_management import login
from cms_packages import install, upload
from e2e import BASE, Client, check
from fixture_store import FixtureStore
from validation import post_json

ROOT = Path(__file__).resolve().parents[1]


def png(noise=False):
    width = 1024 if noise else 1
    height = 768 if noise else 1
    pixels = secrets.token_bytes(width * height * 3) if noise else b"\x22\x55\x99"
    rows = b"".join(b"\x00" + pixels[y * width * 3 : (y + 1) * width * 3] for y in range(height))

    def chunk(kind, data):
        return (
            struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


def zip_files(files):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, value in files.items():
            archive.writestr(name, value)
    return output.getvalue()


def export(client, url, document=None, name="Portable draft"):
    if document is None:
        return client.request(url, binary=True)
    return client.request(
        url,
        "POST",
        raw=json.dumps({"name": name, "design": json.dumps(document)}).encode(),
        content_type="application/json",
        binary=True,
    )


def run():
    with FixtureStore.from_environment() as fixtures:
        verify(fixtures)
    print(
        "PASS Theme exports: editable ZIPs, unsaved snapshots, media/metadata preservation, collision rebasing, replacement versions, permissions, validation and disconnect cleanup",
        flush=True,
    )


def verify(fixtures):
    owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    public = Client()
    previous = props(public, "/")["theme"]["id"]
    suffix = secrets.token_hex(5)
    packages = []
    image_ids = []
    source_bytes = (ROOT / "tests/fixtures/media/logo-transparent.png").read_bytes()
    status, _, body = owner.request(
        "/admin/media/upload", "POST", raw=source_bytes, content_type="image/png"
    )
    check(status == 201, "Export image upload failed")
    image = json.loads(body)
    image_ids.append(image["id"])
    package_filename = (
        "ta_"
        + hashlib.sha256(("theme-asset:" + image["filename"]).encode()).hexdigest()[:32]
        + image["filename"][32:]
    )
    fixtures.update(
        "media_assets",
        {"title": "Portable illustration", "alt": "Library description"},
        [("id", "=", image["id"])],
    )
    base = props(owner, "/admin/themes/create")["baseDocument"]
    document = copy.deepcopy(base)
    document["templates"]["Home"] = [
        {
            "id": "export-section",
            "name": "Portable section",
            "background": "",
            "color": "",
            "padding": 32,
            "columns": 1,
            "align": "left",
            "width": "content",
            "blocks": [
                {
                    "id": "export-title",
                    "type": "heading",
                    "text": "Portable design",
                    "href": "",
                    "image": "",
                    "alt": "",
                    "level": 1,
                },
                {
                    "id": "export-image",
                    "type": "image",
                    "text": "",
                    "href": "",
                    "image": image["url"],
                    "alt": "Design description",
                    "level": 1,
                    "classes": ["frame"],
                },
            ],
        }
    ]
    document["classes"] = {
        "frame": {
            "desktop": {
                "normal": {
                    "border-radius": "16px",
                    "background-image": 'url("' + image["url"] + '")',
                }
            },
            "mobile": {"normal": {"width": "100%"}},
        }
    }
    document["templates"]["SpecialOffers"] = []
    document["templateMeta"] = {"SpecialOffers": {"label": "Special offers", "fallback": "Home"}}
    document["css"] = ':scope { --illustration: url("' + image["url"] + '"); }'
    status, headers, body = post_json(
        owner,
        "/admin/themes/create",
        {"name": "Export " + suffix, "starter": "blank", "design": json.dumps(document)},
    )
    check(status == 303, "Export design creation failed: " + body[:200])
    editor_url = headers["location"]
    identifier = props(owner, editor_url)["studio"]["id"]
    packages.append(identifier)
    url = "/admin/themes/" + identifier + "/export"
    exports = Path(os.environ["TEST_DB_PATH"]).parent / "exports"
    try:
        check(public.request(url)[0] == 303, "Public request exported a private theme")
        check(
            owner.request(url, "POST", {"name": "Invalid", "design": "{}"}, csrf=False)[0] == 419,
            "Export bypassed CSRF",
        )
        before = fixtures.rows(
            "theme_designs", ["draft", "published", "version"], [("id", "=", identifier)], limit=1
        )[0]
        status, headers, data = export(owner, url)
        check(
            status == 200 and headers["content-type"] == "application/zip",
            "Saved design export failed: " + data[:400].decode("utf-8", errors="replace"),
        )
        check(
            "attachment" in headers["content-disposition"]
            and "no-store" in headers["cache-control"],
            "Theme download is not private/attached",
        )
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            files = {name: archive.read(name) for name in archive.namelist()}
        manifest = json.loads(files["cms-package.json"])
        check(
            manifest["layout"] == "builder" and manifest["cmsVersion"] == "2.16.0",
            "Export lost its release and editable renderer",
        )
        check(
            set(files)
            == {
                "cms-package.json",
                "theme-design.json",
                "theme-media.json",
                "media/" + package_filename,
            },
            "Export included unrelated site data",
        )
        check(files["media/" + package_filename] == source_bytes, "Export changed its media bytes")
        media = json.loads(files["theme-media.json"])
        check(
            media[0]["title"] == "Portable illustration"
            and media[0]["alt"] == "Library description",
            "Media metadata was lost",
        )
        unsaved = copy.deepcopy(document)
        unsaved["templates"]["Home"][0]["blocks"][0]["text"] = "An unsaved portable design"
        status, _, snapshot = export(owner, url, unsaved)
        check(status == 200, "Current unsaved design could not be exported")
        after = fixtures.rows(
            "theme_designs", ["draft", "published", "version"], [("id", "=", identifier)], limit=1
        )[0]
        check(before == after, "Export saved/published a draft or changed its optimistic version")
        with zipfile.ZipFile(io.BytesIO(snapshot)) as archive:
            files = {name: archive.read(name) for name in archive.namelist()}
        manifest = json.loads(files["cms-package.json"])
        manifest["slug"] = "portable-" + suffix
        original_prefix = manifest["design"]["mediaPrefix"]
        manifest["design"]["mediaPrefix"] = "https://previous-site.test/uploads/"
        files["cms-package.json"] = json.dumps(manifest).encode()
        design = json.loads(files["theme-design.json"])
        files["theme-design.json"] = (
            json.dumps(design).replace(original_prefix, manifest["design"]["mediaPrefix"]).encode()
        )
        files["media/" + package_filename] = png()
        package = zip_files(files)
        imported = "theme-" + manifest["slug"]
        install(owner, "themes", package)
        packages.append(imported)
        imported_studio = props(owner, "/admin/themes/" + imported + "/design")["studio"]
        imported_document = imported_studio["document"]
        imported_url = imported_document["templates"]["Home"][0]["blocks"][1]["image"]
        check(
            imported_url != image["url"]
            and imported_url.startswith("/theme-assets/" + imported + "/"),
            "An existing different image was overwritten",
        )
        check(
            public.request(image["url"], binary=True)[2] == source_bytes,
            "Import changed the original image",
        )
        check(
            public.request(imported_url, binary=True)[2] == png(),
            "Imported media does not match the package",
        )
        check(
            imported_url
            in imported_document["classes"]["frame"]["desktop"]["normal"]["background-image"]
            and imported_url in imported_document["css"],
            "Nested CSS references did not rebase",
        )
        check(
            imported_studio["version"] == imported_studio["publishedVersion"] == 1
            and not imported_studio["enabled"],
            "A newly installed visual theme was not ready and inactive",
        )
        check(props(public, "/")["theme"]["id"] == previous, "Import activated itself")
        new_image = fixtures.rows(
            "theme_assets",
            ["id", "title", "alt"],
            [("theme_id", "=", imported), ("filename", "=", imported_url.rsplit("/", 1)[1])],
            limit=1,
        )[0]
        check(
            new_image["title"] == media[0]["title"] and new_image["alt"] == media[0]["alt"],
            "Import lost media metadata",
        )
        check(
            owner.request(
                "/admin/themes/" + imported + "/assets/" + str(new_image["id"]) + "/delete",
                "POST",
                {},
            )[0]
            == 422,
            "Imported design images were not protected",
        )
        inspected = upload(owner, "themes", package)
        check(
            owner.request(
                "/admin/themes/install", "POST", {"key": inspected["key"], "replace": "0"}
            )[0]
            == 422,
            "An existing design was silently replaced",
        )
        check(
            owner.request(
                "/admin/themes/install", "POST", {"key": inspected["key"], "replace": "1"}
            )[0]
            == 303,
            "Explicit visual theme replacement failed",
        )
        check(
            props(owner, "/admin/themes/" + imported + "/design")["studio"]["version"] == 2,
            "Replacement did not invalidate stale editors",
        )
        check(
            post_json(
                owner,
                "/admin/themes/" + imported + "/design",
                {
                    "name": "Stale",
                    "design": json.dumps(imported_document),
                    "version": "1",
                    "action": "save",
                },
            )[0]
            == 422,
            "An old editor overwrote an imported design",
        )
        check(
            owner.request("/admin/themes/" + imported + "/enable", "POST", {})[0] == 303,
            "Imported design activation failed",
        )
        check(
            "An unsaved portable design" in public.request("/")[2],
            "Imported theme did not render through SSR",
        )
        invalid = dict(files)
        invalid.pop("media/" + package_filename)
        count_before = fixtures.count("theme_designs")
        check(
            owner.request(
                "/admin/themes/upload",
                "POST",
                raw=zip_files(invalid),
                content_type="application/zip",
            )[0]
            == 422,
            "Missing bundled media was accepted",
        )
        check(
            fixtures.count("theme_designs") == count_before,
            "Invalid archive created a partial design",
        )
        invalid = dict(files)
        bad_manifest = copy.deepcopy(manifest)
        bad_manifest["design"]["file"] = "../escape.json"
        invalid["cms-package.json"] = json.dumps(bad_manifest).encode()
        check(
            owner.request(
                "/admin/themes/upload",
                "POST",
                raw=zip_files(invalid),
                content_type="application/zip",
            )[0]
            == 422,
            "Unsafe design path was accepted",
        )
        invalid = dict(files)
        bad_manifest = copy.deepcopy(manifest)
        bad_manifest["cmsVersion"] = "0.0.0"
        invalid["cms-package.json"] = json.dumps(bad_manifest).encode()
        check(
            owner.request(
                "/admin/themes/upload",
                "POST",
                raw=zip_files(invalid),
                content_type="application/zip",
            )[0]
            == 422,
            "An incompatible visual format was accepted",
        )
        status, _, body = owner.request(
            "/admin/media/upload", "POST", raw=png(True), content_type="image/png"
        )
        check(status == 201, "Streaming export fixture upload failed")
        large = json.loads(body)
        image_ids.append(large["id"])
        large_document = copy.deepcopy(document)
        large_document["templates"]["Home"][0]["blocks"][1]["image"] = large["url"]
        check(
            post_json(
                owner,
                editor_url,
                {
                    "name": "Streaming export",
                    "design": json.dumps(large_document),
                    "version": "1",
                    "action": "save",
                },
            )[0]
            == 200,
            "Streaming export fixture save failed",
        )
        cookie = "; ".join(name + "=" + value for name, value in owner.cookies.items())
        for after_headers in (False, True):
            connection = socket.create_connection((BASE.hostname, BASE.port), timeout=10)
            request = (
                "GET "
                + url
                + " HTTP/1.1\r\nHost: "
                + BASE.netloc
                + "\r\nCookie: "
                + cookie
                + "\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n"
            )
            connection.sendall(request.encode())
            if after_headers:
                check(
                    connection.recv(1024).startswith(b"HTTP/1.1 200"), "Export stream did not start"
                )
            connection.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
            connection.close()
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                time.sleep(0.15)
                if not list(exports.glob("*.zip")):
                    break
            check(
                not list(exports.glob("*.zip")), "Disconnected theme download left a temporary ZIP"
            )
    finally:
        owner.request("/admin/themes/" + previous + "/enable", "POST", {})
        for package in reversed(packages):
            owner.request("/admin/themes/" + package + "/uninstall", "POST", {})
        for row in fixtures.scan("media_assets", ["id"], [("id", ">", image["id"])]):
            image_ids.append(row["id"])
        for image_id in set(image_ids):
            owner.request("/admin/media/" + str(image_id) + "/delete", "POST", {})


if __name__ == "__main__":
    run()
