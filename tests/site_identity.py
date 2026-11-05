"""Verify managed logos, genuine WebP decoding, theme fallback and generic site settings."""

from html.parser import HTMLParser
import json
import os
from pathlib import Path

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
        check(status == 303, "Save site identity returned " + str(status) + ": " + body[:200])

    def themes(logo):
        for slug in ("simple", "fieldnotes", "notebook", "gallery"):
            status, _, source = admin.request("/admin/themes/theme-" + slug + "/preview/frame")
            check(status == 200, "Theme preview failed: " + slug)
            images = Logos(source).images
            if logo:
                check(
                    len(images) == (1 if slug == "simple" else 2)
                    and all(
                        image["src"] == logo and image["alt"] == settings["site_name"]
                        for image in images
                    ),
                    "Theme did not use the configured logo: " + slug,
                )
            else:
                check(not images, "Theme retained a removed logo: " + slug)
                check(settings["site_name"] in source, "Theme omitted the site name: " + slug)

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
                status, _, body = admin.request(
                    "/admin/media/upload", "POST", raw=content, content_type=mime
                )
                check(status == 201, name + " upload: " + str(status) + " " + body[:200])
                image = json.loads(body)
                created.append(image)
                check(
                    image["contentType"] == mime
                    and image["width"] == 120
                    and image["height"] == 40,
                    "Wrong decoded logo dimensions or type",
                )
                save(image["url"])
                check(props(public, "/")["site"]["site_logo"] == image["url"], "Stale logo cache")
                themes(image["url"])
                served = public.request(image["url"], binary=True)
                check(
                    served[0] == 200 and served[1]["content-type"] == mime and served[2] == content,
                    "Logo bytes, transparency or media MIME type changed",
                )
                check(
                    admin.request("/admin/media/" + str(image["id"]) + "/delete", "POST", {})[0]
                    == 422,
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
                "/media/" + "a" * 32 + ".webp",
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
            check(
                admin.request(
                    "/admin/media/upload",
                    "POST",
                    raw=b"RIFF\x04\x00\x00\x00WEBP",
                    content_type="image/webp",
                )[0]
                == 422,
                "A WebP signature without a decodable image was accepted",
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
                admin.request("/admin/media/" + str(image["id"]) + "/delete", "POST", {})[0] == 303,
                "A detached logo could not be deleted",
            )
        admin.request("/admin/logout", "POST", {})
    print(
        "PASS Site identity: generic optional publisher/about fields, transparent PNG, lossy/lossless WebP, all theme logos/fallbacks, live cache invalidation and protected media",
        flush=True,
    )


if __name__ == "__main__":
    run()
