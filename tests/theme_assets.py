"""Theme-owned images stay outside site media and survive a complete package round trip."""

import copy
import hashlib
import io
import json
import os
from pathlib import Path
import secrets
import zipfile

from cms_content import props
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore
from theme_export import install, zip_files, png
from theme_mcp import large_png
from validation import post_json

ROOT = Path(__file__).resolve().parents[1]


def run():
    owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    public = Client()
    previous = props(public, "/")["theme"]["id"]
    packages = []
    with FixtureStore.from_environment() as store:
        original_media = store.count("media_assets")
        try:
            for name in ("Theme image test", "Other image scope"):
                status, headers, _ = post_json(
                    owner, "/admin/themes/create", {"name": name, "starter": "blank"}
                )
                check(status == 303, "Theme creation failed")
                packages.append(props(owner, headers["location"])["studio"]["id"])
            identifier, other = packages
            base = f"/admin/themes/{identifier}"
            upload = f"{base}/assets"
            image_bytes = (ROOT / "tests/fixtures/media/logo-transparent.png").read_bytes()
            check(
                public.request(upload, "POST", raw=image_bytes, content_type="image/png")[0]
                in (303, 401, 403, 419),
                "An anonymous client uploaded a theme image",
            )
            check(
                owner.request(
                    upload, "POST", raw=image_bytes, content_type="image/png", csrf=False
                )[0]
                == 419,
                "Theme upload bypassed CSRF",
            )
            check(
                owner.request(upload, "POST", raw=b"not an image", content_type="image/png")[0]
                == 422,
                "Invalid theme image accepted",
            )
            webp_bytes = (ROOT / "tests/fixtures/media/logo-lossless.webp").read_bytes()
            check(
                owner.request(upload, "POST", raw=webp_bytes, content_type="image/webp")[0] == 422,
                "New WebP theme image accepted",
            )
            status, headers, staged = owner.request(
                upload,
                "POST",
                raw=image_bytes,
                content_type="image/png",
                binary=True,
                extra_headers={"X-File-Name": "Transparent%20theme%20logo.png"},
            )
            check(status == 202 and staged == image_bytes, "Theme image staging changed the bytes")
            check(
                json.loads(owner.request(upload)[2])["images"] == [],
                "An unconfirmed image entered the theme library",
            )
            pending_id = headers["x-upload-id"]
            digest = hashlib.sha256(staged).hexdigest()
            check(
                owner.verify_image(f"/admin/themes/{other}/assets", pending_id, digest, (120, 40))[
                    0
                ]
                == 404,
                "An upload was confirmed for another theme",
            )
            status, _, body = owner.verify_image(upload, pending_id, digest, (120, 40))
            check(status == 201, f"Theme image upload failed: {body[:150]}")
            image = json.loads(body)
            check(
                image["url"].startswith(f"/theme-assets/{identifier}/"),
                "Theme image used the global media route",
            )
            file = store.work / "storage/themes" / identifier / image["filename"]
            check(
                file.read_bytes() == image_bytes, "Theme upload was not stored in its own directory"
            )
            check(
                not (store.work / "storage/media" / image["filename"]).exists(),
                "Theme image entered media storage",
            )
            check(
                store.count("media_assets") == original_media,
                "Theme upload created a site media record",
            )
            status, headers, data = public.request(image["url"], binary=True)
            check(
                status == 200
                and data == image_bytes
                and headers["content-type"] == "image/png"
                and "set-cookie" not in headers,
                "Public theme image response failed",
            )
            check(
                public.request(f"/theme-assets/{other}/{image['filename']}")[0] == 404,
                "Image bytes crossed the owning theme",
            )
            document = props(owner, f"{base}/design")["studio"]["document"]
            document["templates"]["Home"] = [
                {
                    "id": "asset-section",
                    "name": "Theme image",
                    "blocks": [
                        {
                            "id": "asset-image",
                            "type": "image",
                            "image": image["url"],
                            "alt": "Theme-specific illustration",
                        }
                    ],
                }
            ]
            document["css"] = f""":scope {{ --theme-illustration: url("{image['url']}"); }}"""
            payload = {
                "name": "Theme image test",
                "design": json.dumps(document),
                "version": "1",
                "action": "publish",
            }
            status, _, body = post_json(owner, f"{base}/design", payload)
            check(status == 200, f"Owned image design failed native validation: {body[:200]}")
            used = json.loads(owner.request(upload)[2])["images"][0]
            check(used["in_use"], "Theme image dependency was not reported")
            check(
                owner.request(f"{upload}/{str(image['id'])}/delete", "POST", {})[0] == 422,
                "A referenced theme image was deleted",
            )
            cross = {**payload, "version": "1", "name": "Other image scope"}
            check(
                post_json(owner, f"/admin/themes/{other}/design", cross)[0] == 422,
                "A design referenced another theme's image",
            )
            check(
                json.loads(owner.request(f"/admin/themes/{other}/assets")[2])["images"] == [],
                "Theme asset library leaked another theme's files",
            )
            # An unrelated theme's storage does not affect this theme's aggregate budget.
            store.update("theme_assets", {"size": 62 * 1024 * 1024}, [("id", "=", image["id"])])
            check(
                owner.request(upload, "POST", raw=image_bytes, content_type="image/png")[0] == 422,
                "Theme storage aggregate budget was ignored",
            )
            check(
                owner.upload_image(
                    f"/admin/themes/{other}/assets",
                    image_bytes,
                    "image/png",
                    (120, 40),
                )[0]
                == 201,
                "The upload budget was applied across themes",
            )
            store.update("theme_assets", {"size": len(image_bytes)}, [("id", "=", image["id"])])
            # Unused uploads are part of the theme, including packages above the former 10 MB cap.
            large = large_png()
            for _ in range(5):
                check(
                    owner.upload_image(upload, large, "image/png", (1024, 768))[0] == 201,
                    "Unused theme image upload failed",
                )
            status, _, archive = owner.request(f"{base}/export", binary=True)
            check(
                status == 200 and len(archive) > 10 * 1024 * 1024,
                "A larger theme export was not created",
            )
            with zipfile.ZipFile(io.BytesIO(archive)) as package:
                files = {name: package.read(name) for name in package.namelist()}
            metadata = json.loads(files["theme-media.json"])
            check(len(metadata) == 6, "Unused theme images were omitted from export")
            check(
                files[f"media/{image['filename']}"] == image_bytes,
                "Export changed owned image bytes",
            )
            manifest = json.loads(files["cms-package.json"])
            manifest["slug"] = f"owned-image-copy-{secrets.token_hex(5)}"
            copied = f"theme-{manifest['slug']}"
            files["cms-package.json"] = json.dumps(manifest).encode()
            install(owner, "themes", zip_files(files))
            packages.append(copied)
            copied_base = f"/admin/themes/{copied}"
            copied_doc = props(owner, f"{copied_base}/design")["studio"]["document"]
            copied_url = copied_doc["templates"]["Home"][0]["blocks"][0]["image"]
            check(
                copied_url == f"/theme-assets/{copied}/{image['filename']}",
                "Import did not rebase image ownership",
            )
            check(copied_url in copied_doc["css"], "Import did not rebase CSS backgrounds")
            check(
                store.count("theme_assets", [("theme_id", "=", copied)]) == 6,
                "Import dropped unused images",
            )
            check(
                store.count("media_assets") == original_media, "Import polluted the media library"
            )
            check(
                public.request(copied_url, binary=True)[2] == image_bytes,
                "Imported theme image failed",
            )
            check(
                owner.request(f"{copied_base}/enable", "POST", {})[0] == 303,
                "Imported theme activation failed",
            )
            check(
                copied_url in public.request("/")[2],
                "Published renderer filtered out the owned image",
            )
            # Same-name/different-byte updates must retain the prior immutable asset URL.
            files[f"media/{image['filename']}"] = png()
            manifest["version"] = "1.0.1"
            files["cms-package.json"] = json.dumps(manifest).encode()
            install(owner, "themes", zip_files(files), replace=True)
            updated = props(owner, f"{copied_base}/design")["studio"]["document"]
            new_url = updated["templates"]["Home"][0]["blocks"][0]["image"]
            check(
                new_url != copied_url and public.request(new_url, binary=True)[2] == png(),
                "A colliding owned asset was not rebased",
            )
            check(
                public.request(copied_url, binary=True)[2] == image_bytes,
                "An immutable theme image was overwritten",
            )
            check(
                owner.request(f"{base}/uninstall", "POST", {})[0] == 303, "Theme uninstall failed"
            )
            check(not file.parent.exists(), "Theme uninstall left its owned files behind")
            check(
                public.request(copied_url, binary=True)[0] == 200,
                "Removing the source theme deleted another theme's image",
            )
            check(
                store.count("theme_assets", [("theme_id", "=", identifier)]) == 0,
                "Uninstall left asset metadata",
            )
            check(
                store.count("media_assets") == original_media,
                "Theme lifecycle modified site media records",
            )
        finally:
            owner.request(f"/admin/themes/{previous}/enable", "POST", {})
            for identifier in reversed(packages):
                owner.request(f"/admin/themes/{identifier}/uninstall", "POST", {})
    print(
        "PASS Theme assets: isolated Storage/ORM, auth/CSRF, native image validation, scoped cache and SQL budgets, CSS/rendering, used-image protection, all-image export above 10 MB, import rebasing/collisions and complete uninstall",
        flush=True,
    )


if __name__ == "__main__":
    run()
