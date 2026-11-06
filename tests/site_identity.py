"""Verify PNG uploads, legacy WebP logos, theme fallback and generic site settings."""

from html.parser import HTMLParser
import hashlib
import json
import os
from pathlib import Path
import secrets

from cms_content import props
from e2e import Client, check
from fixture_store import FixtureStore

ROOT = Path(__file__).resolve().parents[1]


class Logos(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.images = []
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "img" and "site-brand-logo" in values.get("class", "").split():
            self.images.append(values)


def run():
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
        "Site identity login",
    )
    original = props(public, "/")["site"]
    settings = {**original, "site_name": "Example organization", "publisher_name": ""}
    created = []

    def save(logo):
        status, _, body = admin.request("/admin/settings", "POST", {**settings, "site_logo": logo})
        check(status == 303, f"Save site identity returned {str(status)}: {body[:200]}")

    def themes(logo):
        for slug in ("simple", "fieldnotes", "notebook", "gallery"):
            status, _, source = admin.request(f"/admin/themes/theme-{slug}/preview/frame")
            check(status == 200, f"Theme preview failed: {slug}")
            images = Logos(source).images
            if logo:
                check(
                    len(images) == (1 if slug == "simple" else 2)
                    and all(
                        image["src"] == logo and image["alt"] == settings["site_name"]
                        for image in images
                    ),
                    f"Theme did not use the configured logo: {slug}",
                )
            else:
                check(not images, f"Theme retained a removed logo: {slug}")
                check(settings["site_name"] in source, f"Theme omitted the site name: {slug}")

    try:
        with FixtureStore.from_environment() as fixtures:
            page = admin.request("/admin/settings")[2]
            check(
                'name="publisher_name"' in page
                and 'name="about_site"' in page
                and 'name="site_logo"' in page
                and 'name="author_name"' not in page
                and 'name="author_bio"' not in page,
                "Settings retained personal blog fields",
            )
            save("")
            themes("")
            for name in ("logo-transparent.png", "logo-lossless.webp", "logo-lossy.webp"):
                content = (ROOT / "tests/fixtures/media" / name).read_bytes()
                mime = "image/png" if name.endswith(".png") else "image/webp"
                if mime == "image/png":
                    status, _, body = admin.upload_image(
                        "/admin/media/upload", content, mime, (120, 40)
                    )
                    check(status == 201, f"{name} upload: {str(status)} {body[:200]}")
                    image = json.loads(body)
                    check(
                        image["contentType"] == mime
                        and image["width"] == 120
                        and image["height"] == 40,
                        "Wrong confirmed logo dimensions or type",
                    )
                else:
                    check(
                        admin.request(
                            "/admin/media/upload", "POST", raw=content, content_type=mime
                        )[0]
                        == 415,
                        "New WebP logo upload was accepted",
                    )
                    filename = f"{secrets.token_hex(16)}.webp"
                    (fixtures.work / "storage/media" / filename).write_bytes(content)
                    identifier = fixtures.create(
                        "media_assets",
                        [
                            {
                                "filename": filename,
                                "title": name,
                                "alt": "Legacy logo",
                                "mime_type": mime,
                                "width": 120,
                                "height": 40,
                                "size": len(content),
                            }
                        ],
                    )[0]
                    image = {"id": identifier, "url": f"/media/{filename}"}
                created.append(image)
                save(image["url"])
                check(props(public, "/")["site"]["site_logo"] == image["url"], "Stale logo cache")
                themes(image["url"])
                served = public.request(image["url"], binary=True)
                check(
                    served[0] == 200 and served[1]["content-type"] == mime and served[2] == content,
                    "Logo bytes, transparency or media MIME type changed",
                )
                check(
                    admin.request(f"/admin/media/{str(image['id'])}/trash", "POST", {})[0] == 422,
                    "A configured site logo could be deleted",
                )
                check(
                    fixtures.rows("media_assets", ["filename"], [("id", "=", image["id"])])
                    and public.request(image["url"], binary=True)[2] == content,
                    "Blocked logo deletion changed the asset",
                )
            current = created[-1]["url"]
            for invalid in (
                "https://example.test/logo.png",
                "data:image/png;base64,AAAA",
                f"/media/{'a' * 32}.webp",
                "/media/../logo.png",
            ):
                response = admin.request(
                    "/admin/settings", "POST", {**settings, "site_logo": invalid}
                )
                check(response[0] == 422, "An unmanaged logo URL was accepted")
                check(
                    props(public, "/")["site"]["site_logo"] == current,
                    "Invalid logo changed settings",
                )
            original_count = fixtures.count("media_assets")
            truncated_png = (ROOT / "tests/fixtures/media/logo-transparent.png").read_bytes()[:33]
            upload = "/admin/media/upload"
            status, headers, staged = admin.request(
                upload, "POST", raw=truncated_png, content_type="image/png", binary=True
            )
            check(status == 202 and staged == truncated_png, "The server decoded staged pixels")
            pending_id = headers["x-upload-id"]
            pending = [("key", "=", pending_id)]
            temporary = fixtures.work / "storage/image-uploads" / pending_id
            check(temporary.is_dir(), "Unconfirmed upload was not staged privately")
            check(
                fixtures.count("media_assets") == original_count,
                "Unconfirmed image entered the media library",
            )
            fixtures.update("image_uploads", {"expires_epoch": 0}, pending)
            check(
                admin.verify_image(
                    upload, pending_id, hashlib.sha256(staged).hexdigest(), (120, 40)
                )[0]
                == 404,
                "An expired image upload was confirmed",
            )
            fixtures.call("expire_image_uploads")
            check(
                fixtures.count("image_uploads", pending) == 0 and not temporary.exists(),
                "Expired image staging was not removed",
            )
            save("")
            themes("")
            check(
                props(public, "/")["site"]["site_logo"] == "", "Removing the logo left a stale URL"
            )
    finally:
        check(admin.request("/admin/settings", "POST", original)[0] == 303, "Restore site identity")
        for image in created:
            check(
                admin.delete_media(image["id"])[0] == 303,
                "A detached logo could not be deleted",
            )
        admin.request("/admin/logout", "POST", {})
    print(
        "PASS Site identity: transparent PNG, legacy WebP logos, upload expiry, theme fallbacks, cache invalidation and protected media",
        flush=True,
    )


if __name__ == "__main__":
    run()
