"""Exercise definition-driven collections, structured values and database-backed roles."""

import json
import os
from pathlib import Path
import re
import secrets

from e2e import Client, check
from fixture_store import FixtureStore
from cms_content import props
from cms_packages import install, zip_bytes

ROOT = Path(__file__).resolve().parents[1]
HEADERS = {"X-Well-Data": "true", "Accept": "application/json"}


def login(client, email, password):
    client.request("/admin/login")
    check(
        client.request("/admin/login", "POST", {"email": email, "password": password})[0] == 303,
        "Structure test login",
    )


def field(key, kind, public=True, listed=False, filtered=False, required=False):
    return {
        "key": key,
        "label": key.title(),
        "kind": kind,
        "help": "",
        "required": required,
        "publicVisible": public,
        "inList": listed,
        "filterable": filtered,
        "options": [],
    }


def verify_presentation(owner, public, fixtures, definition, prefix, slug, identifier, suffix):
    original_site = props(owner, "/admin/settings")["site"]
    original_name = props(owner, "/admin/account")["auth"]["admin"]["name"]
    original_theme = next(
        row["id"]
        for row in fixtures.scan("cms_packages", ["id", "kind", "enabled"])
        if row["kind"] == "theme" and row["enabled"]
    )
    theme_slug = f"runtime-{suffix}"
    theme_id = f"theme-{theme_slug}"
    region = f"runtime_{suffix}"
    manifest = {
        "apiVersion": 4,
        "cmsVersion": "2.16.0",
        "kind": "theme",
        "slug": theme_slug,
        "name": "Runtime partial theme",
        "version": "1.0.0",
        "layout": "runtime-layout",
        "assets": {"stylesheet": "theme.css", "views": "views"},
        "fields": [],
        "templates": [{"name": "RuntimeDetail", "label": "Runtime detail", "scope": "detail"}],
        "navigation": [{"key": region, "name": "Runtime links", "maxLinks": 5}],
    }
    template = """<props item="ContentItemView" />
<main data-runtime-template="true">{{ item.title }}<span :if="item.fields">{{ item.fields['price'] | string }}</span></main>
"""
    install(
        owner,
        "themes",
        zip_bytes(
            manifest,
            {
                "public/theme.css": ".runtime-template {color:#123456;}",
                "views/RuntimeDetail.well.html": template,
            },
        ),
    )
    link_id = None
    try:
        check(
            owner.request(f"/admin/themes/{theme_id}/enable", "POST", {})[0] == 303,
            "Activate a partial theme with an arbitrary layout",
        )
        definition["template"] = "RuntimeDetail"
        check(
            owner.request(
                f"/admin/content-types/{definition['key']}/save",
                "POST",
                {"definition": json.dumps(definition)},
            )[0]
            == 303,
            "Assign a named public template",
        )
        check(
            'data-runtime-template="true"' in public.request(f"/{prefix}/{slug}")[2],
            "Named partial theme did not render an initial HTML request",
        )
        preview_path = f"/admin/collections/{definition['key']}/preview"
        draft = {
            "id": str(identifier),
            "title": "Unsaved themed preview",
            "slug": slug,
            "custom_fields": json.dumps({"price": 35.5, "secret": "Private preview value"}),
        }
        status, headers, html = owner.request(preview_path, "POST", draft)
        check(
            status == 200
            and headers.get("x-frame-options") == "SAMEORIGIN"
            and headers.get("cache-control") == "private, no-store"
            and headers.get("x-robots-tag") == "noindex, nofollow"
            and re.search(
                r'<main data-runtime-template="true">Unsaved themed preview.*<span>35\.5</span>',
                html,
            )
            and "Private preview value" not in html,
            "The editor preview did not render the active template and public draft fields",
        )
        status, _, payload = owner.request(preview_path, "POST", draft, extra_headers=HEADERS)
        page = json.loads(payload)
        check(
            status == 200
            and page["component"] == "RuntimeDetail"
            and page["props"]["theme"]["id"] == theme_id
            and page["props"]["auth"] is None
            and page["props"]["csrfToken"] is None,
            "The preview used the wrong theme or exposed administration props",
        )
        check(
            owner.request(preview_path, "POST", draft, csrf=False)[0] == 419,
            "Content preview bypassed CSRF validation",
        )
        check(
            "Unsaved themed preview" not in public.request(f"/{prefix}/{slug}")[2],
            "Preview changed the published item",
        )
        check(public.request("/")[0] == 200, "Partial theme lost its standard homepage fallback")
        frame = owner.request(f"/admin/themes/{theme_id}/preview/frame/{prefix}/{slug}")
        check(
            frame[0] == 200
            and frame[1].get("x-frame-options") == "SAMEORIGIN"
            and 'data-runtime-template="true"' in frame[2],
            "Dynamic collection preview frame",
        )
        menu = {
            "id": "",
            "location": region,
            "label": "Runtime content link",
            "content_id": str(identifier),
            "collection_key": "",
            "url": "",
            "position": "0",
            "new_tab": "0",
        }
        check(
            owner.request("/admin/navigation/save", "POST", menu)[0] == 303,
            "Link arbitrary content in a theme-declared region",
        )
        link_id = fixtures.rows("menu_links", ["id"], [("location", "=", region)])[0]["id"]
        check(
            props(public, "/")["navigation"][region][0]["url"] == f"/{prefix}/{slug}",
            "Dynamic navigation region or managed content address",
        )
        changed_site = {
            **original_site,
            "home_mode": "page",
            "home_type": definition["key"],
            "home_page": str(identifier),
            "publisher_name": "Independent site profile",
        }
        check(
            owner.request("/admin/settings", "POST", changed_site)[0] == 303,
            "Configure a content-backed homepage",
        )
        check(
            props(public, "/")["item"]["id"] == identifier,
            "Homepage did not use its selected content",
        )
        check(
            public.request(f"/{prefix}/{slug}")[1]["location"] == "/",
            "Homepage content retained a duplicate canonical address",
        )
        check(
            props(owner, "/admin/account")["auth"]["admin"]["name"] == original_name,
            "Site profile changed the administrator account",
        )
        check(
            owner.request("/admin/settings", "POST", original_site)[0] == 303,
            "Restore original homepage",
        )
        definition["template"] = "MissingRuntimeTemplate"
        check(
            owner.request(
                f"/admin/content-types/{definition['key']}/save",
                "POST",
                {"definition": json.dumps(definition)},
            )[0]
            == 303,
            "Configure an unavailable template",
        )
        fallback = public.request(f"/{prefix}/{slug}")
        check(
            fallback[0] == 200 and "content-field-values" in fallback[2],
            "Missing named template lost its standard field-aware fallback",
        )
    finally:
        owner.request("/admin/settings", "POST", original_site)
        definition["template"] = "ContentDetail"
        owner.request(
            f"/admin/content-types/{definition['key']}/save",
            "POST",
            {"definition": json.dumps(definition)},
        )
        owner.request(f"/admin/themes/{original_theme}/enable", "POST", {})
        owner.request(f"/admin/themes/{theme_id}/uninstall", "POST", {})
        if link_id is not None:
            owner.request(f"/admin/navigation/{str(link_id)}/delete", "POST", {})
        fixtures.delete("navigation_regions", [("key", "=", region)])


def run():
    owner = Client()
    public = Client()
    login(owner, os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    suffix = secrets.token_hex(4)
    key = f"product_{suffix}"
    role = f"product_editor_{suffix}"
    prefix = f"products-{suffix}"
    base = f"/admin/collections/{key}"
    email = f"product-editor-{suffix}@example.test"
    password = secrets.token_urlsafe(20)
    definition = {
        "key": key,
        "name": "Products",
        "singular": "Product",
        "publicPath": prefix,
        "publicVisible": True,
        "hasArchive": True,
        "enabled": True,
        "dedicatedAccess": True,
        "features": ["image", "seo", "revisions", "schedule"],
        "template": "ContentDetail",
        "archiveTemplate": "ContentIndex",
        "fields": [
            field("price", "number", listed=True, filtered=True, required=True),
            field("stock", "boolean", listed=True, filtered=True),
            field("secret", "text", public=False, listed=True),
            field("banner", "image"),
        ],
    }
    identifiers = []
    with FixtureStore.from_environment() as fixtures:
        try:
            created = owner.request(
                "/admin/content-types/create", "POST", {"definition": json.dumps(definition)}
            )
            check(created[0] == 303, f"Create runtime content definition: {created[2][:300]}")
            editor = props(owner, f"{base}/new")
            check(
                editor["contentType"]["key"] == key and not editor["hasCategories"] is False,
                "Generic editor definition",
            )
            navigation = editor["adminNavigation"]
            check(
                any(link["href"] == base for group in navigation for link in group["links"]),
                "Definition was absent from native admin navigation",
            )
            image_file = ROOT / "public/images/coast.jpg"
            status, _, body = owner.upload_image(
                "/admin/media/upload",
                image_file.read_bytes(),
                "image/jpeg",
                (1000, 750),
            )
            check(status == 201, "Custom field image upload")
            image = json.loads(body)
            values = {
                "price": 0,
                "stock": False,
                "secret": f"PRIVATE-{suffix}",
                "banner": image["url"],
            }
            data = {
                "id": "",
                "title": "A",
                "slug": "welcome-to-haxepress",
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
            missing = owner.request(
                f"{base}/save", "POST", {**data, "custom_fields": json.dumps({"stock": False})}
            )
            check(missing[0] == 422, "Publication accepted a missing required custom field")
            check(
                owner.request(f"{base}/working-copy", "POST", {**data, "draft_version": "1"})[0]
                == 200,
                "Generic new working copy",
            )
            restored = props(owner, f"{base}/new?draft={editor['draftKey']}")
            check(
                json.loads(restored["workingCopy"]["data"]["custom_fields"])["price"] == 0,
                "Working copy lost structured values",
            )
            status, headers, body = owner.request(f"{base}/save", "POST", data)
            check(status == 303, f"Save structured content: {body[:300]}")
            identifier = int(re.search(r"/(\d+)/edit", headers["location"]).group(1))
            identifiers.append(identifier)
            data["id"] = str(identifier)
            page = props(public, f"/{prefix}/{data['slug']}")
            check(
                page["item"]["fields"]["price"] == 0 and page["item"]["fields"]["stock"] is False,
                "Zero/false custom values changed",
            )
            check(
                "secret" not in page["item"]["fields"] and values["secret"] not in json.dumps(page),
                "Private custom value leaked",
            )
            listing = props(public, f"/{prefix}?field_price=0&field_stock=false")
            check(
                listing["resultCount"] == 1 and len(listing["items"]) == 1,
                "Native custom-field filter",
            )
            check("secret" not in listing["items"][0]["fields"], "Private list projection leaked")
            check(
                props(public, f"/{prefix}?field_price=11")["resultCount"] == 0,
                "Specific custom-field query reused another filter",
            )
            check(
                props(public, f"/{prefix}?field_secret=wrong")["resultCount"] == 1,
                "Private fields became public predicates",
            )
            admin_list = props(owner, base)
            check(
                admin_list["items"][0]["fields"]["secret"] == values["secret"],
                "Admin list did not project its requested private scalar",
            )
            media_id = fixtures.rows(
                "media_assets", ["id"], [("filename", "=", Path(image["url"]).name)]
            )[0]["id"]
            check(
                owner.request(f"/admin/media/{str(media_id)}/trash", "POST", {})[0] == 422,
                "A referenced custom image was moved to the trash",
            )
            history = json.loads(owner.request(f"{base}/{str(identifier)}/history")[2])["revisions"]
            snapshot = json.loads(
                owner.request(f"{base}/{str(identifier)}/history/{str(history[0]['id'])}")[2]
            )["snapshot"]
            check(
                snapshot["fields"]["price"] == 0
                and snapshot["fields"]["secret"] == values["secret"],
                "Revision omitted native custom values",
            )
            renamed = f"{prefix}-new"
            definition["publicPath"] = renamed
            check(
                owner.request(
                    f"/admin/content-types/{key}/save",
                    "POST",
                    {"definition": json.dumps(definition)},
                )[0]
                == 303,
                "Change collection path",
            )
            redirect = public.request(f"/{prefix}/{data['slug']}?q=kept")
            check(
                redirect[0] == 301
                and redirect[1]["location"] == f"/{renamed}/{data['slug']}?q=kept",
                "Old collection address did not redirect",
            )
            check(
                owner.request(f"/admin/content-types/{key}/delete", "POST", {})[0] == 422,
                "Removed a populated definition",
            )
            verify_presentation(
                owner, public, fixtures, definition, renamed, data["slug"], identifier, suffix
            )
            old_banner = fixtures.rows(
                "content_values",
                ["id", "value", "value_text"],
                [("content_id", "=", identifier), ("field_key", "=", "banner")],
            )[0]
            fixtures.update(
                "content_values",
                {
                    "value": json.dumps("https://example.test/external.png"),
                    "value_text": "https://example.test/external.png",
                },
                [("id", "=", old_banner["id"])],
            )
            fresh_definition = {**definition, "description": "Refresh the schema boundary"}
            owner.request(
                f"/admin/content-types/{key}/save",
                "POST",
                {"definition": json.dumps(fresh_definition)},
            )
            sanitized = props(public, f"/{renamed}/{data['slug']}")
            check(
                sanitized["item"]["fields"].get("banner") is None,
                "An incompatible stored image bypassed the upload boundary",
            )
            fixtures.update(
                "content_values",
                {"value": old_banner["value"], "value_text": old_banner["value_text"]},
                [("id", "=", old_banner["id"])],
            )
            owner.request(
                f"/admin/content-types/{key}/save",
                "POST",
                {"definition": json.dumps(definition)},
            )
            grants = [f"content.{key}", "account", "publish"]
            result = owner.request(
                "/admin/roles/create",
                "POST",
                {
                    "key": role,
                    "name": "Product editor",
                    "description": "Scoped product access",
                    "enabled": "1",
                    "capabilities": json.dumps(grants),
                },
            )
            check(result[0] == 303, f"Create database role: {result[2][:300]}")
            result = owner.request(
                "/admin/team/save",
                "POST",
                {
                    "id": "",
                    "name": "Product editor",
                    "email": email,
                    "role": role,
                    "active": "1",
                    "password": password,
                },
            )
            check(result[0] == 303, "Assign custom role")
            writer = Client()
            login(writer, email, password)
            check(
                writer.request("/admin/content")[0] == 403
                and writer.request("/admin/roles")[0] == 403,
                "Scoped role gained another collection or role management",
            )
            check(
                props(writer, base)["total"] == 0,
                "Scoped role saw another author's private administration rows",
            )
            check(
                writer.request(f"{base}/{str(identifier)}/edit")[0] == 403,
                "Scoped role edited another author's content",
            )
            user_editor = props(writer, f"{base}/new")
            draft = {
                **data,
                "id": "",
                "title": "Owned product",
                "slug": f"owned-{suffix}",
                "draft_key": user_editor["draftKey"],
                "status": "draft",
                "custom_fields": json.dumps({"price": 3, "stock": True}),
            }
            result = writer.request(f"{base}/save", "POST", draft)
            check(result[0] == 303, "Save within dedicated collection permission")
            identifiers.append(int(re.search(r"/(\d+)/edit", result[1]["location"]).group(1)))
            check(
                owner.request(f"/admin/roles/{role}/delete", "POST", {})[0] == 422,
                "Removed a role that is assigned to an account",
            )
            check(
                owner.request(
                    f"/admin/roles/{role}/save",
                    "POST",
                    {
                        "key": role,
                        "name": "Product editor",
                        "description": "",
                        "enabled": "1",
                        "capabilities": json.dumps(["account"]),
                    },
                )[0]
                == 303,
                "Change role grants",
            )
            check(
                writer.request(base)[0] == 403,
                "Permission removal did not apply to an existing session",
            )
            check(
                owner.request(
                    f"/admin/roles/{role}/save",
                    "POST",
                    {
                        "key": role,
                        "name": "Product editor",
                        "description": "",
                        "enabled": "0",
                        "capabilities": json.dumps(["account"]),
                    },
                )[0]
                == 303,
                "Disable custom role",
            )
            check(
                writer.request("/admin/account")[0] == 303,
                "Disabled role retained an administration session",
            )
            definition["publicVisible"] = False
            check(
                owner.request(
                    f"/admin/content-types/{key}/save",
                    "POST",
                    {"definition": json.dumps(definition)},
                )[0]
                == 303,
                "Make collection private",
            )
            check(
                public.request(f"/{renamed}")[0] == 404
                and public.request(f"/{renamed}/{data['slug']}")[0] == 404,
                "Private collection remained public",
            )
        finally:
            for identifier in identifiers:
                owner.request(f"{base}/{str(identifier)}/delete", "POST", {})
            fixtures.delete("admins", [("email", "=", email)])
            owner.request(f"/admin/roles/{role}/delete", "POST", {})
            fixtures.delete("editor_drafts", [("kind", "=", key)])
            owner.request(f"/admin/content-types/{key}/delete", "POST", {})
            owner.request("/admin/logout", "POST", {})
    print(
        "PASS Dynamic CMS: runtime collections, dedicated role grants, scalar/list/filter privacy, zero/false values, working copies, revisions, image references and retained permalink redirects",
        flush=True,
    )


if __name__ == "__main__":
    run()
