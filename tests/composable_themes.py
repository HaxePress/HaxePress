"""Verify composable themes over native HTTP, SSR, ORM queries and managed media."""

import copy
import json
import os
from pathlib import Path
import secrets

from cms_content import props
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore
from validation import post_json

ROOT = Path(__file__).resolve().parents[1]


def block(identifier, kind="container", **values):
    return {
        "id": identifier,
        "type": kind,
        "text": "",
        "href": "",
        "image": "",
        "alt": "",
        "level": 2,
        "children": [],
        **values,
    }


def section(identifier, blocks):
    return {
        "id": identifier,
        "name": identifier,
        "padding": 24,
        "columns": 1,
        "align": "left",
        "width": "content",
        "color": "",
        "background": "",
        "blocks": blocks,
    }


def run():
    owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    public = Client()
    with FixtureStore.from_environment() as fixtures:
        verify(owner, public, fixtures)
    print(
        "PASS Composable themes: nested DOM, responsive/hover/class CSS, components, templates, scoped/cached feeds, legacy reads, normalization, media dependencies and bounded validation",
        flush=True,
    )


def verify(owner, public, fixtures):
    original_theme = props(public, "/")["theme"]["id"]
    original_site = props(public, "/")["site"]
    name = f"Composable {secrets.token_hex(5)}"
    status, headers, body = owner.request(
        "/admin/themes/create", "POST", {"name": name, "starter": "content"}
    )
    check(status == 303, f"Create composable theme: {body[:150]}")
    editor_url = headers["location"]
    studio = props(owner, editor_url)["studio"]
    identifier = studio["id"]
    base = f"/admin/themes/{identifier}"
    data_url = f"{editor_url}/data"
    document = studio["document"]
    media_id = None
    category = f"Source {secrets.token_hex(6)}"
    version = 1

    def save(value, publish=False):
        nonlocal version
        status, headers, body = post_json(
            owner,
            editor_url,
            {
                "name": name,
                "design": json.dumps(value),
                "version": str(version),
                "action": "publish" if publish else "save",
            },
        )
        if status == 200:
            version = json.loads(body)["version"]
        return status, headers, body

    def preview(value, scope="Home", normalize=False):
        values = {"design": json.dumps(value), "scope": scope}
        if normalize:
            values["normalize"] = "1"
        return post_json(owner, data_url, values)

    try:
        legacy = {
            key: copy.deepcopy(document[key]) for key in ["tokens", "header", "footer", "templates"]
        }
        legacy["schema"] = 1
        fixtures.update("theme_designs", {"draft": json.dumps(legacy)}, [("id", "=", identifier)])
        check(
            props(owner, editor_url)["studio"]["document"]["schema"] == 2,
            "Legacy design was not upgraded for editing",
        )
        check(
            json.loads(
                fixtures.rows("theme_designs", ["draft"], [("id", "=", identifier)], limit=1)[0][
                    "draft"
                ]
            )["schema"]
            == 1,
            "Reading a legacy design rewrote the database",
        )

        timestamp = "2026-11-05 10:00:00"
        fixtures.create(
            "items",
            [
                {
                    "title": f"Composable source {str(index).zfill(3)}",
                    "slug": f"source-{category.split()[-1]}-{str(index)}",
                    "excerpt": "Bounded summary",
                    "content": "This body must not be selected by a theme source.",
                    "category": category,
                    "image": "",
                    "image_alt": "",
                    "content_type": "entry",
                    "status": "published",
                    "featured": 0,
                    "reading_minutes": 1,
                    "version": 1,
                    "author_id": 0,
                    "published_at": timestamp,
                    "created_at": timestamp,
                    "updated_at": timestamp,
                }
                for index in range(25)
            ],
        )
        uploaded = owner.upload_image(
            "/admin/media/upload",
            (ROOT / "public/images/coast.jpg").read_bytes(),
            "image/jpeg",
            (1000, 750),
        )
        check(uploaded[0] == 201, "Composable image upload failed")
        image = json.loads(uploaded[2])
        media_id = image["id"]
        image_url = image["url"]
        escaped_image = image_url.replace("/media/", r"/m\65 dia/")
        title = block(
            "hero-title",
            "heading",
            level=1,
            text="A composed layout",
            styles={
                "desktop": {
                    "normal": {"font-size": "72px", "letter-spacing": "-2px"},
                    "hover": {"color": "#703cc1"},
                },
                "mobile": {"normal": {"font-size": "36px"}},
            },
        )
        grid = block(
            "grid",
            children=[
                block(
                    "left",
                    children=[
                        title,
                        block("description", "text", text="An editable nested layout"),
                    ],
                ),
                block(
                    "right",
                    styles={
                        "desktop": {
                            "normal": {
                                "background-image": f'url("{escaped_image}")',
                                "min-height": "240px",
                                "background-size": "cover",
                                "border-radius": "24px",
                            }
                        }
                    },
                ),
            ],
            styles={
                "desktop": {
                    "normal": {
                        "display": "grid",
                        "grid-template-columns": "1.2fr 0.8fr",
                        "gap": "48px",
                    }
                },
                "mobile": {"normal": {"grid-template-columns": "minmax(0, 1fr)"}},
            },
        )
        repeat = block(
            "cards",
            "repeat",
            source="feed:used",
            children=[
                block(
                    "card",
                    classes=["card"],
                    children=[
                        block(
                            "card-title",
                            "heading",
                            bindings={"text": "item.title", "href": "item.url"},
                        ),
                        block("card-text", "text", bindings={"text": "item.excerpt"}),
                    ],
                )
            ],
            styles={
                "desktop": {
                    "normal": {
                        "display": "grid",
                        "grid-template-columns": "repeat(2, minmax(0, 1fr))",
                        "gap": "24px",
                    }
                },
                "mobile": {"normal": {"grid-template-columns": "minmax(0, 1fr)"}},
            },
        )
        component = {
            "name": "Notice",
            "sections": [
                section("notice-section", [block("notice-text", "text", text="Reusable notice")])
            ],
        }
        document["schema"] = 2
        document["components"] = {"notice": component}
        document["templates"]["Home"] = [
            section("hero-section", [grid]),
            section(
                "cards-section",
                [
                    repeat,
                    block("notice-one", "component", component="notice"),
                    block("notice-two", "component", component="notice"),
                ],
            ),
        ]
        document["templates"]["LandingPage"] = [
            section(
                "landing-section",
                [block("landing-title", "heading", level=1, text="Custom landing template")],
            )
        ]
        document["templateMeta"] = {"LandingPage": {"label": "Landing page", "fallback": "Home"}}
        document["classes"] = {
            "card": {
                "desktop": {
                    "normal": {"padding": "24px", "border-radius": "16px"},
                    "hover": {"transform": "translateY(-4px)"},
                }
            }
        }
        document["css"] = (
            "/* Designer's stylesheet */\n.card { border: 1px solid #ccd6e4; }\n@media (min-width: 1200px) { :scope { --layout-gap: 32px; } }"
        )
        document["feeds"] = [
            {
                "id": "used",
                "name": "Used feed",
                "collection": "entry",
                "limit": 2,
                "category": category,
                "tag": "",
                "query": "Composable source",
                "order": "title",
                "direction": "ASC",
            },
            {
                "id": "unused",
                "name": "Unused feed",
                "collection": "page",
                "limit": 24,
                "category": "",
                "tag": "",
                "query": "",
                "order": "id",
                "direction": "DESC",
            },
        ]

        with fixtures.guard(summaryLimits={data_url: 2}, bodyPaths={}):
            status, _, body = preview(document, normalize=True)
        check(status == 200, f"Scoped source or CSS normalization failed: {body[:200]}")
        normalized = json.loads(body)
        check(set(normalized["feeds"]) == {"used"}, "Unused source was resolved")
        rows = normalized["feeds"]["used"]
        check(
            [row["title"] for row in rows] == ["Composable source 000", "Composable source 001"],
            "Source filtering/sorting/limit is incorrect",
        )
        check(all("content" not in row for row in rows), "Source projected content bodies")
        normalized_background = normalized["document"]["templates"]["Home"][0]["blocks"][0][
            "children"
        ][1]["styles"]["desktop"]["normal"]["background-image"]
        check(
            image_url in normalized_background and "\\65" not in normalized_background,
            "Escaped CSS image URL was not canonicalized",
        )
        check(
            fixtures.rows("theme_designs", ["version"], [("id", "=", identifier)], limit=1)[0][
                "version"
            ]
            == 1,
            "Transient preview persisted a draft",
        )
        document = normalized["document"]

        invalid = copy.deepcopy(document)
        invalid["templates"]["Home"][0]["blocks"][0]["children"][0]["children"][0]["tag"] = "script"
        check(save(invalid)[0] == 422, "Executable HTML tag accepted")
        for css in [
            '@import "https://example.test/theme.css";',
            ".card { background: url(https://example.test/image.jpg); }",
            "} body { display: none; }",
            '.card { content: "</style><script>alert(1)</script>"; }',
        ]:
            invalid = copy.deepcopy(document)
            invalid["css"] = css
            check(save(invalid)[0] == 422, "Unsafe or unbalanced stylesheet accepted")
        invalid = copy.deepcopy(document)
        invalid["components"]["notice"]["sections"][0]["blocks"].append(
            block("component-cycle", "component", component="notice")
        )
        check(save(invalid)[0] == 422, "Reusable component cycle accepted")
        invalid = copy.deepcopy(document)
        invalid["templates"]["Home"][1]["blocks"][0]["source"] = "feed:missing"
        check(save(invalid)[0] == 422, "Missing content source accepted")
        invalid = copy.deepcopy(document)
        invalid["templates"]["Home"][0]["blocks"][0]["bindings"] = {"text": "auth.admin.email"}
        check(save(invalid)[0] == 422, "Private data binding accepted")
        deep = block("deep-0")
        cursor = deep
        for index in range(1, 18):
            child = block(f"deep-{str(index)}")
            cursor["children"] = [child]
            cursor = child
        invalid = copy.deepcopy(document)
        invalid["templates"]["Home"][0]["blocks"].append(deep)
        check(save(invalid)[0] == 422, "Excessive design nesting accepted")

        check(save(document, True)[0] == 200, "Composed theme publish failed")
        check(
            owner.request(f"{base}/enable", "POST", {})[0] == 303, "Composed theme activate failed"
        )
        public_props = props(public, "/")
        check(set(public_props["themeFeeds"]) == {"used"}, "Public source context is incorrect")
        check(len(public_props["themeFeeds"]["used"]) == 2, "Public source lost its SQL limit")
        html = public.request("/")[2]
        for expected in [
            "A composed layout",
            "Reusable notice",
            "Composable source 000",
            "@scope (.hp-design)",
            "grid-template-columns:1.2fr 0.8fr",
            "max-width:600px",
        ]:
            check(expected in html, f"Composed SSR output is missing: {expected}")
        check(html.count("Reusable notice") >= 2, "Shared component did not render both instances")
        check(
            owner.request(f"/admin/media/{str(media_id)}/delete", "POST", {})[0] == 422,
            "CSS background image was deleted",
        )
        props(public, "/")
        with fixtures.guard(blockDatabase=True):
            check(
                public.request("/")[0] == 200, "Published source cache did not serve a warm request"
            )
        active_manifest = json.loads(
            fixtures.rows("cms_packages", ["manifest"], [("id", "=", identifier)], limit=1)[0][
                "manifest"
            ]
        )
        check(
            any(
                template["name"] == "LandingPage" and template["scope"] == "home"
                for template in active_manifest["templates"]
            ),
            "Custom template was not published to the CMS",
        )
        unknown_template = {
            **original_site,
            "home_mode": "collection",
            "home_type": "entry",
            "home_template": "MissingThemeTemplate",
        }
        check(
            owner.request("/admin/settings", "POST", unknown_template)[0] == 303,
            "Set fallback template",
        )
        fallback_props = props(public, "/")
        check(
            len(fallback_props["themeFeeds"]["used"]) == 2,
            "Fallback rendering used a different source scope",
        )
        check("A composed layout" in public.request("/")[2], "Fallback design did not render")
        settings = {
            **original_site,
            "home_mode": "collection",
            "home_type": "entry",
            "home_template": "LandingPage",
        }
        check(
            owner.request("/admin/settings", "POST", settings)[0] == 303,
            "Assign custom homepage template failed",
        )
        check(
            "Custom landing template" in public.request("/")[2],
            "CMS did not resolve its assigned custom template",
        )
        removed = copy.deepcopy(document)
        del removed["templates"]["LandingPage"]
        del removed["templateMeta"]["LandingPage"]
        check(save(removed, True)[0] == 422, "A template assigned to the homepage could be removed")
    finally:
        owner.request("/admin/settings", "POST", original_site)
        owner.request(f"/admin/themes/{original_theme}/enable", "POST", {})
        owner.request(f"{base}/uninstall", "POST", {})
        fixtures.delete("items", [("category", "=", category)])
        if media_id is not None:
            owner.request(f"/admin/media/{str(media_id)}/delete", "POST", {})


if __name__ == "__main__":
    run()
