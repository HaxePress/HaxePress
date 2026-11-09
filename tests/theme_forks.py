"""Bundled themes follow the application; a fork of any theme belongs to the site."""

import hashlib
import io
import json
import os
from pathlib import Path
import re
import zipfile

from cms_content import props
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore
from validation import post_json

ROOT = Path(__file__).resolve().parents[1]
PACKAGES_ROOT = Path(os.environ.get("CMS_TEST_PACKAGES_PATH", ROOT / "private/packages"))
BUNDLED = ["fieldnotes", "notebook", "gallery"]
ACCENT = "#345678"
DYNAMIC = re.compile(r'nonce="[^"]+"|value="[^"]{20,}"|content="[^"]{20,}"')


def run():
    owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    public = Client()
    with FixtureStore.from_environment() as store:
        verify(owner, public, store)
    print(
        "PASS Theme forks: bundled themes refuse uploads and removal; packaged, built-in and visual themes fork with their files, settings, designs and images; forks download, update and uninstall on their own",
        flush=True,
    )


def theme_ids(store):
    return {row["id"] for row in store.rows("cms_packages", ["id"], [("kind", "=", "theme")])}


def fork(owner, store, theme):
    before = theme_ids(store)
    status, headers, body = owner.request(f"/admin/themes/{theme}/fork", "POST", {})
    check(status == 303, f"Forking {theme} returned {status}: {body[:300]}")
    created = theme_ids(store) - before
    check(len(created) == 1, f"Forking {theme} did not add exactly one theme")
    return created.pop(), headers["location"]


def package(store, theme):
    rows = store.rows(
        "cms_packages",
        ["directory", "settings", "enabled", "author", "name", "manifest"],
        [("id", "=", theme)],
        limit=1,
    )
    check(len(rows) == 1, f"{theme} is not installed")
    return rows[0]


def views(store, theme):
    folder = store.work / "storage/extensions/installed" / package(store, theme)["directory"]
    return {
        path.relative_to(folder).as_posix(): path.read_bytes()
        for path in sorted((folder / "views").rglob("*.well.html"))
    }


def page(client, path):
    status, _, body = client.request(path)
    check(status == 200, f"{path} returned {status}")
    return DYNAMIC.sub("", body)


def activate(owner, theme):
    status, _, body = owner.request(f"/admin/themes/{theme}/enable", "POST", {})
    check(status == 303, f"Activating {theme} returned {status}: {body[:200]}")


def edited(archive, view, original, replacement):
    """The downloaded archive with one view changed, as a theme author would edit it."""
    output = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(archive)) as source:
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as target:
            for name in source.namelist():
                data = source.read(name)
                if name == view:
                    check(original.encode() in data, f"{view} no longer contains {original}")
                    data = data.replace(original.encode(), replacement.encode(), 1)
                target.writestr(name, data)
    return output.getvalue()


def replace(owner, archive):
    status, _, body = owner.request(
        "/admin/themes/upload", "POST", raw=archive, content_type="application/zip"
    )
    check(status == 201, f"The edited fork was not accepted: {body[:300]}")
    inspected = json.loads(body)
    check(inspected["installedVersion"], "The edited fork was not recognized as an update")
    status, _, body = owner.request(
        "/admin/themes/install", "POST", {"key": inspected["key"], "replace": "1"}
    )
    check(status == 303, f"The edited fork was not installed: {body[:300]}")


def verify(owner, public, store):
    original_theme = props(public, "/")["theme"]["id"]
    owner_name = props(owner, "/admin")["auth"]["admin"]["name"]
    version = json.loads((ROOT / "cms.json").read_text())["version"]
    created = []
    try:
        listing = owner.request("/admin/themes")[2]
        for slug in BUNDLED:
            theme = f"theme-{slug}"
            check(f"/admin/themes/{theme}/fork" in listing, f"{theme} has no fork action")
            check(f"/admin/themes/{theme}/uninstall" not in listing, f"{theme} offers removal")
            status, _, body = owner.request(f"/admin/themes/{theme}/uninstall", "POST", {})
            check(status == 422 and "cannot be removed" in body, f"{theme} was removed")
        shipped = (PACKAGES_ROOT / f"notebook-{version}.zip").read_bytes()
        status, _, body = owner.request(
            "/admin/themes/upload", "POST", raw=shipped, content_type="application/zip"
        )
        check(
            status == 422 and "Fork the theme to change it." in body,
            f"A ZIP replaced a bundled theme: {status} {body[:200]}",
        )

        values = props(owner, "/admin/themes/theme-notebook/settings")["values"]
        values["accent"] = ACCENT
        status, _, _ = owner.request("/admin/themes/theme-notebook/settings", "POST", values)
        check(status == 303, "Notebook settings were not saved")
        notebook = package(store, "theme-notebook")
        copy, location = fork(owner, store, "theme-notebook")
        created.append(copy)
        check(location == "/admin/themes?notice=forked", f"Forking redirected to {location}")
        forked = package(store, copy)
        manifest = json.loads(forked["manifest"])
        check(
            forked["enabled"] == 0
            and forked["name"] == "Notebook copy"
            and forked["author"] == owner_name
            and manifest["slug"] == copy.removeprefix("theme-")
            and json.loads(forked["settings"]) == json.loads(notebook["settings"]),
            f"The Notebook fork did not keep its settings or take its own identity: {forked}",
        )
        check(
            views(store, copy) == views(store, "theme-notebook"),
            "The Notebook fork's views differ from the original",
        )
        listing = owner.request("/admin/themes")[2]
        check(f"/admin/themes/{copy}/uninstall" in listing, "A fork cannot be removed")
        check(f"/admin/themes/{copy}/download" in listing, "A fork cannot be downloaded")

        status, headers, archive = owner.request(f"/admin/themes/{copy}/download", binary=True)
        check(
            status == 200 and headers["content-type"] == "application/zip",
            f"Downloading the fork returned {status}",
        )
        with zipfile.ZipFile(io.BytesIO(archive)) as downloaded:
            downloaded_manifest = json.loads(downloaded.read("cms-package.json"))
        check(downloaded_manifest["slug"] == manifest["slug"], "The download is another theme")
        check(
            public.request(f"/admin/themes/{copy}/download")[0] in (303, 401, 403),
            "A visitor downloaded theme files",
        )
        replace(
            owner,
            edited(archive, "views/Home.well.html", "{{ t('The latest content') }}", "Edited fork"),
        )
        check(json.loads(package(store, copy)["settings"])["accent"] == ACCENT, "Update lost")
        activate(owner, copy)
        check("Edited fork" in page(public, "/"), "The edited fork is not rendered")
        activate(owner, "theme-notebook")
        check("Edited fork" not in page(public, "/"), "Editing the fork changed Notebook")

        activate(owner, "theme-simple")
        simple_home = page(public, "/")
        simple_detail = page(public, "/about")
        simple_copy, _ = fork(owner, store, "theme-simple")
        created.append(simple_copy)
        copied_views = views(store, simple_copy)
        check(
            {"views/Home.well.html", "views/SiteLayout.well.html"} <= set(copied_views),
            f"The Simple fork lacks the application views: {sorted(copied_views)}",
        )
        activate(owner, simple_copy)
        check(page(public, "/") == simple_home, "The Simple fork renders another home page")
        check(page(public, "/about") == simple_detail, "The Simple fork renders another page")
        status, _, archive = owner.request(f"/admin/themes/{simple_copy}/download", binary=True)
        check(status == 200, "The Simple fork could not be downloaded")
        replace(
            owner,
            edited(archive, "views/Home.well.html", "{{ t('The latest content') }}", "Own Simple"),
        )
        check("Own Simple" in page(public, "/"), "The Simple fork does not use its own views")
        check(
            owner.request("/admin/themes/theme-simple/download")[0] == 404,
            "The built-in theme was offered as a package download",
        )

        status, headers, _ = post_json(
            owner, "/admin/themes/create", {"name": "Forked design", "starter": "blank"}
        )
        check(status == 303, "The design to fork was not created")
        design = props(owner, headers["location"])["studio"]["id"]
        created.append(design)
        image_bytes = (ROOT / "tests/fixtures/media/logo-transparent.png").read_bytes()
        upload = f"/admin/themes/{design}/assets"
        status, headers, _ = owner.request(
            upload, "POST", raw=image_bytes, content_type="image/png", binary=True
        )
        check(status == 202, "The design image was not staged")
        status, _, body = owner.verify_image(
            upload, headers["x-upload-id"], hashlib.sha256(image_bytes).hexdigest(), (120, 40)
        )
        check(status == 201, f"The design image was not saved: {body[:200]}")
        image = json.loads(body)
        studio = props(owner, f"/admin/themes/{design}/design")["studio"]
        document = studio["document"]
        document["templates"]["Home"] = [
            {
                "id": "fork-section",
                "name": "Forked image",
                "blocks": [
                    {
                        "id": "fork-image",
                        "type": "image",
                        "image": image["url"],
                        "alt": "Forked illustration",
                    }
                ],
            }
        ]
        status, _, body = post_json(
            owner,
            f"/admin/themes/{design}/design",
            {
                "name": "Forked design",
                "design": json.dumps(document),
                "version": str(studio["version"]),
                "action": "publish",
            },
        )
        check(status == 200, f"The design was not published: {body[:200]}")
        design_copy, location = fork(owner, store, design)
        created.append(design_copy)
        check(location == f"/admin/themes/{design_copy}/design", "A design fork did not open")
        copied = props(owner, location)["studio"]
        copied_image = image["url"].replace(
            f"/theme-assets/{design}/", f"/theme-assets/{design_copy}/"
        )
        copied_source = json.dumps(copied["document"])
        check(
            copied_image in copied_source and design not in copied_source,
            "The design fork still points at the original theme's images",
        )
        check(copied["publishedVersion"] == 1, "The design fork lost its published version")
        status, _, served = public.request(copied_image, binary=True)
        check(status == 200 and served == image_bytes, "The design fork's image is missing")
        status, _, _ = owner.request(f"/admin/themes/{design}/uninstall", "POST", {})
        check(status == 303, "The original design could not be removed")
        created.remove(design)
        status, _, served = public.request(copied_image, binary=True)
        check(
            status == 200 and served == image_bytes, "Removing the original took the fork's image"
        )
        activate(owner, design_copy)
        check(copied_image in page(public, "/"), "The design fork does not render its image")
    finally:
        activate(owner, original_theme)
        for theme in created:
            owner.request(f"/admin/themes/{theme}/uninstall", "POST", {})


if __name__ == "__main__":
    run()
