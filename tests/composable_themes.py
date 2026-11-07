"""Verify composable themes over native HTTP, server rendering, ORM queries and managed media."""

import copy
import json
import os
from pathlib import Path
import re
import secrets
import subprocess

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


def field(key, kind, public=True, listed=False):
    return {
        "key": key,
        "label": key.title(),
        "kind": kind,
        "help": "",
        "required": False,
        "publicVisible": public,
        "inList": listed,
        "filterable": False,
        "options": [],
    }


def create_products(owner, suffix):
    """A collection with a public list field, a public detail-only field and a private field."""
    key = f"composable_{suffix}"
    prefix = f"composable-{suffix}"
    definition = {
        "key": key,
        "name": "Composable products",
        "singular": "Composable product",
        "publicPath": prefix,
        "publicVisible": True,
        "hasArchive": True,
        "enabled": True,
        "dedicatedAccess": False,
        "features": ["image"],
        "template": "ContentDetail",
        "archiveTemplate": "ContentIndex",
        "fields": [
            field("price", "number", listed=True),
            field("note", "text"),
            field("secret", "text", public=False, listed=True),
        ],
    }
    created = owner.request(
        "/admin/content-types/create", "POST", {"definition": json.dumps(definition)}
    )
    check(created[0] == 303, f"Create custom field collection: {created[2][:300]}")
    base = f"/admin/collections/{key}"
    editor = props(owner, f"{base}/new")
    slug = f"product-{suffix}"
    values = {"price": 35.5, "note": f"NOTE-{suffix}", "secret": f"SECRET-{suffix}"}
    data = {
        "id": "",
        "title": f"Composable product {suffix}",
        "slug": slug,
        "excerpt": "",
        "content": "",
        "category": "",
        "image": "",
        "image_alt": "",
        "status": "published",
        "featured": "0",
        "published_at": "2026-11-04",
        "version": "1",
        "draft_key": editor["draftKey"],
        "tags": "",
        "stay": "1",
        "custom_fields": json.dumps(values),
    }
    status, headers, body = owner.request(f"{base}/save", "POST", data)
    check(status == 303, f"Save custom field content: {body[:300]}")
    identifier = int(re.search(r"/(\d+)/edit", headers["location"]).group(1))
    return {
        "key": key,
        "base": base,
        "path": f"/{prefix}/{slug}",
        "id": identifier,
        "values": values,
    }


def editor_stylesheet(document):
    """The editor preview's stylesheet for a document (resources/js/themes/builder/styles.ts)."""
    generated = subprocess.run(
        ["node", str(ROOT / "tests/design_stylesheet.mjs")],
        input=json.dumps(document),
        text=True,
        capture_output=True,
        check=True,
        cwd=ROOT,
    )
    return generated.stdout


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
    products = None
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

        # One class's mobile rule must beat another class's and the node's own desktop rules.
        document["classes"]["split"] = {
            "desktop": {"normal": {"flex-direction": "row", "display": "flex"}}
        }
        document["classes"]["collapse"] = {
            "desktop": {"normal": {"gap": "24px"}},
            "tablet": {"normal": {"gap": "16px"}},
            "mobile": {"normal": {"flex-direction": "column", "padding": "16px"}},
        }
        document["templates"]["Home"][0]["blocks"].append(
            block(
                "hero-actions",
                classes=["split", "collapse"],
                styles={
                    "desktop": {"normal": {"padding": "48px"}},
                    "mobile": {"normal": {"gap": "8px"}},
                },
            )
        )
        # Custom fields follow the item's public/list visibility in lists and on detail pages.
        products = create_products(owner, secrets.token_hex(4))
        document["feeds"].append(
            {
                "id": "products",
                "name": "Products",
                "collection": products["key"],
                "limit": 4,
                "category": "",
                "tag": "",
                "query": "",
                "order": "id",
                "direction": "DESC",
            }
        )
        document["templates"]["Home"][1]["blocks"].append(
            block(
                "product-cards",
                "repeat",
                source="feed:products",
                children=[
                    block("product-price", "text", bindings={"text": "item.fields.price"}),
                    block("product-note", "text", bindings={"text": "item.fields.note"}),
                    block("product-secret", "text", bindings={"text": "item.fields.secret"}),
                    block(
                        "product-badge",
                        "element",
                        tag="span",
                        attributes={"aria-label": "Price"},
                        bindings={"text": "item.fields.price"},
                    ),
                    block(
                        "product-priced",
                        "text",
                        text="Priced",
                        condition={
                            "field": "item.fields.price",
                            "operator": "present",
                            "value": "",
                        },
                    ),
                    block(
                        "product-noted",
                        "text",
                        text="Noted in list",
                        condition={"field": "item.fields.note", "operator": "present", "value": ""},
                    ),
                ],
            )
        )
        document["templates"]["ContentDetail"].append(
            section(
                "product-detail",
                [
                    block("detail-price", "text", bindings={"text": "item.fields.price"}),
                    block("detail-note", "text", bindings={"text": "item.fields.note"}),
                    block("detail-secret", "text", bindings={"text": "item.fields.secret"}),
                ],
            )
        )
        status, _, body = preview(document, normalize=True)
        check(status == 200, f"Custom field bindings were rejected: {body[:200]}")
        normalized = json.loads(body)
        check(
            set(normalized["feeds"]) == {"used", "products"},
            "The custom field source was not resolved",
        )
        check(
            [row["fields"] for row in normalized["feeds"]["products"]] == [{"price": 35.5}],
            "A list source exposed custom fields outside its public list fields",
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
        for path in [
            "item.fields.price.amount",
            "item.fields.Price",
            "item.title.length",
            "site.links.home",
        ]:
            invalid = copy.deepcopy(document)
            invalid["templates"]["Home"][0]["blocks"][0]["bindings"] = {"text": path}
            status, _, body = save(invalid)
            check(
                status == 422 and "item.fields.<key>" in json.loads(body)["error"],
                f"A binding the renderer cannot read was accepted: {path}",
            )
            invalid = copy.deepcopy(document)
            invalid["templates"]["Home"][0]["blocks"][0]["condition"] = {
                "field": path,
                "operator": "present",
                "value": "",
            }
            check(save(invalid)[0] == 422, f"A condition the renderer cannot read: {path}")
        invalid = copy.deepcopy(document)
        invalid["templates"]["Home"][0]["blocks"][0]["attributes"] = {"data-kind": "grid"}
        status, _, body = save(invalid)
        check(
            status == 422
            and "Only HTML element blocks take attributes" in json.loads(body)["error"]
            and "container block grid" in json.loads(body)["error"],
            "Attributes on a container were accepted although only elements render them",
        )
        for font in ["16px Inter", "Inter,,serif", '"Inter', "Inter,", "   ", "inherit"]:
            invalid = copy.deepcopy(document)
            invalid["tokens"]["font"] = font
            status, _, body = save(invalid)
            check(
                status == 422 and "font family name or font stack" in json.loads(body)["error"],
                f"An invalid font stack was accepted: {font}",
            )
        for font in [
            "sans",
            "'DM Sans', Arial, sans-serif",
            "IBM Plex Sans, -apple-system, system-ui, sans-serif",
            '"Bob\'s Serif 2", Georgia, serif',
        ]:
            accepted = copy.deepcopy(document)
            accepted["tokens"]["font"] = font
            check(preview(accepted)[0] == 200, f"A valid font stack was rejected: {font}")
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
        check(
            set(public_props["themeFeeds"]) == {"used", "products"},
            "Public source context is incorrect",
        )
        check(len(public_props["themeFeeds"]["used"]) == 2, "Public source lost its SQL limit")
        html = public.request("/")[2]
        for expected in ["A composed layout", "Reusable notice", "Composable source 000"]:
            check(expected in html, f"Composed server HTML is missing: {expected}")
        design_link = re.search(r'<link rel="stylesheet" href="(/theme-design/[^"]+\.css)"', html)
        check(design_link is not None, "Composed server HTML did not link its design stylesheet")
        css_status, css_headers, css = public.request(design_link.group(1))
        check(
            css_status == 200
            and "text/css" in css_headers.get("content-type", "")
            and "immutable" in css_headers.get("cache-control", "")
            and "set-cookie" not in css_headers,
            "Composed design stylesheet was not served as a cacheable, session-free asset",
        )
        for expected in [
            "@scope (.hp-design)",
            "grid-template-columns:1.2fr 0.8fr",
            "max-width:600px",
        ]:
            check(expected in css, f"Composed design stylesheet is missing: {expected}")
        check(
            css == editor_stylesheet(document),
            "The published stylesheet differs from the editor preview's",
        )
        check(
            css.count("@media(max-width:900px)") == 1 and css.count("@media(max-width:600px)") == 1,
            "Responsive rules were not grouped into one tablet and one mobile block",
        )
        actions = '.hp-design [data-design-node="hero-actions"]'
        order = [
            css.find(".hp-design .design-class-collapse{gap:24px;}"),
            css.find(".hp-design .design-class-split{display:flex;flex-direction:row;}"),
            css.find(f"{actions}{{padding:48px;}}"),
            css.find("@media(max-width:900px){"),
            css.find("@media(max-width:600px){"),
            css.find(".hp-design .design-class-collapse{flex-direction:column;padding:16px;}"),
            css.find(f"{actions}{{gap:8px;}}"),
        ]
        check(
            -1 not in order and order == sorted(order),
            f"Stylesheet cascade order is wrong: {order}",
        )
        price = re.escape("35.5")
        for pattern, message in [
            (rf'data-design-node="product-price"[^>]*>{price}</p>', "List custom field"),
            (
                rf'<span [^>]*aria-label="Price" data-design-node="product-badge"[^>]*>{price}</span>',
                "Element custom field",
            ),
            (r'data-design-node="product-priced"[^>]*>Priced</p>', "Custom field condition"),
        ]:
            check(re.search(pattern, html) is not None, f"{message} did not render")
        check(
            products["values"]["note"] not in html
            and products["values"]["secret"] not in html
            and "Noted in list" not in html,
            "A list rendered a custom field outside its public list fields",
        )
        detail = public.request(products["path"])[2]
        check(
            re.search(rf'data-design-node="detail-price"[^>]*>{price}</p>', detail) is not None
            and re.search(
                rf'data-design-node="detail-note"[^>]*>{products["values"]["note"]}</p>', detail
            )
            is not None
            and products["values"]["secret"] not in detail,
            "A detail page did not follow the public custom field rules",
        )
        check(html.count("Reusable notice") >= 2, "Shared component did not render both instances")
        check(
            owner.request(f"/admin/media/{str(media_id)}/trash", "POST", {})[0] == 422,
            "CSS background image was moved to the trash",
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
        if products is not None:
            owner.request(f"{products['base']}/{str(products['id'])}/delete", "POST", {})
            fixtures.delete("editor_drafts", [("kind", "=", products["key"])])
            owner.request(f"/admin/content-types/{products['key']}/delete", "POST", {})
        fixtures.delete("items", [("category", "=", category)])
        if media_id is not None:
            owner.request(f"/admin/media/{str(media_id)}/trash", "POST", {})
            owner.request(f"/admin/media/{str(media_id)}/permanent-delete", "POST", {})


if __name__ == "__main__":
    run()
