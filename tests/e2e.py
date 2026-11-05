#!/usr/bin/env python3
"""Exercise the running HxWell/Crossbyte app through real HTTP requests.

Creates and removes only uniquely named test content, categories, and subscribers.
Uses ADMIN_EMAIL / ADMIN_PASSWORD from .env unless overridden in the environment.
"""

import csv
import html
import http.client
import http.cookies
import io
import json
import os
from pathlib import Path
import re
import time
import urllib.parse
import uuid
import xml.etree.ElementTree as ElementTree
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser

ROOT = Path(__file__).resolve().parents[1]
ENV = {}
for line in (ROOT / ".env").read_text().splitlines():
    if "=" in line and not line.lstrip().startswith("#"):
        key, value = line.split("=", 1)
        ENV[key] = value.strip().strip('"')
BASE = urllib.parse.urlsplit(
    os.environ.get("TEST_URL", ENV.get("APP_URL", "http://127.0.0.1:3000"))
)


class Client:
    def __init__(self):
        self.cookies = {}
        self.csrf = ""

    def request(
        self,
        path,
        method="GET",
        data=None,
        csrf=True,
        raw=None,
        content_type="application/octet-stream",
        binary=False,
        extra_headers=None,
    ):
        headers = {"Accept-Encoding": "identity"}
        if self.cookies:
            headers["Cookie"] = "; ".join(key + "=" + value for key, value in self.cookies.items())
        body = None
        if data is not None:
            values = dict(data)
            if csrf:
                values["_token"] = self.csrf
            body = urllib.parse.urlencode(values)
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        if raw is not None:
            body = raw
            headers["Content-Type"] = content_type
            if csrf:
                headers["X-CSRF-TOKEN"] = self.csrf
        headers.update(extra_headers or {})
        connection = http.client.HTTPConnection(BASE.hostname, BASE.port or 80, timeout=120)
        try:
            connection.request(method, path, body, headers)
            response = connection.getresponse()
            fields = response.getheaders()
            normalized = {}
            for key, value in fields:
                name = key.lower()
                normalized[name] = (
                    normalized[name] + ", " + value
                    if name == "vary" and name in normalized
                    else value
                )
            payload = response.read()
            text = payload if binary else payload.decode("utf-8")
            for key, value in fields:
                if key.lower() == "set-cookie":
                    parsed = http.cookies.SimpleCookie()
                    parsed.load(value)
                    for name, cookie in parsed.items():
                        self.cookies[name] = cookie.value
            token = None if binary else re.search(r'name="_token" value="([^"]+)"', text)
            if token:
                self.csrf = html.unescape(token.group(1))
            if not binary and dict((k.lower(), v) for k, v in fields).get("x-inertia") == "true":
                page = json.loads(text)
                if page.get("props", {}).get("csrfToken"):
                    self.csrf = page["props"]["csrfToken"]
            return response.status, normalized, text
        finally:
            connection.close()


def check(condition, message):
    if not condition:
        raise AssertionError(message)


class InertiaPageParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.pages = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "div" and values.get("id") == "app" and "data-page" in values:
            self.pages.append(json.loads(values["data-page"]))


def run():
    public = Client()
    admin = Client()
    passed = []
    content_id = None
    subscriber_id = None
    category_id = None
    original_featured = None
    suffix = uuid.uuid4().hex[:12]
    slug = "integration-content-" + suffix
    email = "integration-" + suffix + "@example.com"

    def mark(name):
        passed.append(name)
        print("PASS " + name, flush=True)

    try:
        status, headers, text = public.request("/")
        check(status == 200 and "The latest content" in text, "home page")
        check("::" not in text, "unresolved Haxe template data")
        check(headers.get("x-content-type-options") == "nosniff", "security headers")
        check(
            "set-cookie" not in headers and not public.cookies, "public homepage creates a session"
        )
        parser = InertiaPageParser()
        parser.feed(text)
        check(
            len(parser.pages) == 1 and parser.pages[0]["component"] == "Home",
            "single Inertia hydration root",
        )
        check(
            isinstance(parser.pages[0]["props"]["items"], list),
            "HTML strings were not replaced with props",
        )
        covers = [parser.pages[0]["props"]["featured"], *parser.pages[0]["props"]["items"]]
        check(
            all(item["image"].startswith("/media/") for item in covers),
            "existing site covers were not moved into upload storage",
        )
        version = parser.pages[0]["version"]
        check(
            bool(version) and "x-inertia" in headers.get("vary", "").lower(),
            f"Inertia version and Vary header: version={version!r}, vary={headers.get('vary')!r}",
        )
        stylesheet = re.search(r'<link rel="stylesheet" href="(/build/[^\"]+)"', text)
        check(stylesheet is not None, "Vite stylesheet is missing")
        mark("English React SSR, single hydration root, Vite assets, and response headers")
        inertia_headers = {
            "X-Inertia": "true",
            "X-Inertia-Version": version,
            "Accept": "application/json",
        }
        status, xhr_headers, payload = public.request(
            "/content?category=Getting%20started", extra_headers=inertia_headers
        )
        check(
            status == 200,
            f"Inertia navigation status={status}, headers={xhr_headers}, body={payload[:150]!r}",
        )
        check(
            xhr_headers.get("x-inertia") == "true",
            f"Inertia JSON header missing: headers={xhr_headers}, body={payload[:180]!r}",
        )
        page = json.loads(payload)
        check(
            status == 200
            and xhr_headers.get("x-inertia") == "true"
            and page["component"] == "ContentIndex",
            "Inertia page navigation",
        )
        check(
            len(page["props"]["items"]) == 1 and "category=Getting%20started" in page["url"],
            "Inertia props and query-string URL",
        )
        check(
            page["props"].get("auth") is None
            and page["props"].get("csrfToken") is None
            and "set-cookie" not in xhr_headers,
            "public Inertia session isolation",
        )
        status, _, payload = public.request(
            "/content?category=Getting%20started",
            extra_headers={
                **inertia_headers,
                "X-Inertia-Partial-Component": "ContentIndex",
                "X-Inertia-Partial-Data": "items",
            },
        )
        partial = json.loads(payload)
        check(
            status == 200 and "items" in partial["props"] and "query" not in partial["props"],
            "partial props reload",
        )
        status, mismatch, _ = public.request(
            "/content?category=Getting%20started",
            extra_headers={**inertia_headers, "X-Inertia-Version": "outdated-version"},
        )
        check(
            status == 409
            and "category=Getting%20started" in mismatch.get("x-inertia-location", ""),
            "asset-version reload preserves query",
        )
        mark("Inertia JSON navigation, partial reloads, versioning, and stateless public props")
        status, _, text = public.request("/content?category=Getting%20started")
        check(
            status == 200
            and "Create and organize content" in text
            and "Welcome to HaxePress" not in text,
            "category filtering",
        )
        status, _, text = public.request("/content?q=media")
        check(status == 200 and "Manage your media library" in text, "search")
        check(
            public.request("/content/your-next-content-item")[0] == 404,
            "draft is public",
        )
        check(public.request("/content/no-such-content")[0] == 404, "404 route")
        for path in ["/about", stylesheet.group(1), "/rss.xml"]:
            page_status, page_headers, _ = public.request(path)
            check(
                page_status == 200 and "set-cookie" not in page_headers,
                "public route or asset creates sessions: " + path,
            )
        mark("Session-free public routes, site search, filters, draft privacy and 404 pages")
        status, headers, _ = public.request("/admin/login")
        check(
            status == 200 and "path=/admin" in headers.get("set-cookie", "").lower(),
            "admin cookies are not scoped to /admin",
        )
        for path in [
            "/admin",
            "/admin/content",
            "/admin/content/new",
            "/admin/content/1/edit",
            "/admin/categories",
            "/admin/subscribers",
            "/admin/subscribers/export",
            "/admin/settings",
        ]:
            status, headers, _ = public.request(path)
            check(
                status == 303 and headers.get("location") == "/admin/login",
                "unprotected admin route: " + path,
            )
        status, headers, _ = public.request(
            "/admin/content/save", "POST", {"title": "Unauthorized"}
        )
        check(
            status == 303 and headers.get("location") == "/admin/login", "unprotected admin write"
        )
        for path in ["/admin/categories/save", "/admin/categories/1/delete"]:
            status, headers, _ = public.request(path, "POST", {"name": "Unauthorized"})
            check(
                status == 303 and headers.get("location") == "/admin/login",
                "unprotected category write: " + path,
            )
        fixture = (ROOT / "public/images/coast.jpg").read_bytes()
        status, headers, _ = public.request(
            "/admin/media/upload", "POST", raw=fixture, content_type="image/jpeg"
        )
        check(
            status == 303 and headers.get("location") == "/admin/login", "unprotected image upload"
        )
        mark("Shared admin route-group guard protects read and write routes")
        check(
            public.request(
                "/admin/content/save", "POST", {"title": "Missing CSRF token"}, csrf=False
            )[0]
            == 419,
            "missing admin CSRF token accepted",
        )
        check(
            public.request(
                "/admin/categories/save", "POST", {"name": "Missing CSRF token"}, csrf=False
            )[0]
            == 419,
            "category write missing CSRF token accepted",
        )
        check(
            public.request("/subscribe", "POST", {"email": "not-an-email"})[0] == 422,
            "invalid email accepted",
        )
        mark("Admin-only CSRF protection and server-side validation")
        admin.request("/admin/login")
        start = time.monotonic()
        status, headers, _ = admin.request(
            "/admin/login",
            "POST",
            {
                "email": os.environ.get("TEST_ADMIN_EMAIL", ENV["ADMIN_EMAIL"]),
                "password": os.environ.get("TEST_ADMIN_PASSWORD", ENV["ADMIN_PASSWORD"]),
            },
        )
        check(status == 303 and headers.get("location") == "/admin", "admin login")
        status, headers, text = admin.request("/admin")
        check(
            status == 200 and "Sign in" in text and headers.get("cache-control") == "no-store",
            "authenticated dashboard",
        )
        for path in [
            "/admin/content",
            "/admin/content/new",
            "/admin/content/1/edit",
            "/admin/categories",
            "/admin/settings",
            "/admin/subscribers",
        ]:
            page_status, _, page = admin.request(path)
            check(page_status == 200 and "::" not in page, "authenticated page rendering: " + path)
            if path == "/admin/content/new":
                check(
                    "Cover image URL" not in page and 'id="cover-url"' not in page,
                    "manual cover URL field remains",
                )
                editor = InertiaPageParser()
                editor.feed(page)
                check(
                    editor.pages[0]["props"]["item"]["image"] == "",
                    "new content should not have an automatic stock cover",
                )
                check("No cover image yet." in page, "empty upload-only cover state")
        mark(
            "HxWell admin auth guard and regenerated session ("
            + str(round(time.monotonic() - start, 2))
            + "s)"
        )
        category_name = "Integration " + suffix
        check(
            admin.request(
                "/admin/categories/save", "POST", {"id": "", "name": "  " + category_name + "  "}
            )[0]
            == 303,
            "create category",
        )
        status, _, payload = admin.request("/admin/categories", extra_headers=inertia_headers)
        category_props = json.loads(payload)["props"]
        created = next(
            (value for value in category_props["categoryList"] if value["name"] == category_name),
            None,
        )
        check(
            status == 200 and created is not None and created["items"] == 0,
            "new category management row and content item count",
        )
        category_id = created["id"]
        _, _, public_categories = public.request("/content", extra_headers=inertia_headers)
        check(
            category_name in json.loads(public_categories)["props"]["categories"],
            "public categories are not database-backed",
        )
        for name in ["", "x" * 81, category_name.upper()]:
            check(
                admin.request("/admin/categories/save", "POST", {"id": "", "name": name})[0] == 422,
                "invalid or duplicate category accepted: " + name,
            )
        status, redirect, _ = admin.request(
            "/admin/categories/save",
            "POST",
            {"id": "", "name": category_name.upper()},
            extra_headers=inertia_headers,
        )
        check(
            status == 303 and redirect.get("location") == "/admin/categories",
            "Inertia category validation redirect",
        )
        status, _, payload = admin.request("/admin/categories", extra_headers=inertia_headers)
        check(
            json.loads(payload)["props"]["errors"].get("category"),
            "category validation errors missing",
        )
        check(
            admin.request(
                "/admin/categories/save", "POST", {"id": "invalid", "name": category_name}
            )[0]
            == 404,
            "malformed category id accepted",
        )
        status, _, text = admin.request("/admin/content/new")
        check(category_name in text, "new category missing from content item editor")
        check(
            admin.request(
                "/admin/categories/" + str(category_id) + "/delete", "POST", {}, csrf=False
            )[0]
            == 419,
            "category deletion missing CSRF accepted",
        )
        mark("Eloquent category creation, normalization, duplicate validation and editor choices")
        check(
            admin.request(
                "/admin/media/upload", "POST", raw=fixture, content_type="image/jpeg", csrf=False
            )[0]
            == 419,
            "image upload missing CSRF accepted",
        )
        check(
            admin.request(
                "/admin/media/upload",
                "POST",
                raw=b'<svg onload="alert(1)"></svg>',
                content_type="image/png",
            )[0]
            == 415,
            "disguised SVG accepted",
        )
        check(
            admin.request(
                "/admin/media/upload",
                "POST",
                raw=bytes.fromhex("89504e470d0a1a0a") + b"not-an-image",
                content_type="image/png",
            )[0]
            == 422,
            "corrupted image accepted",
        )
        check(
            admin.request("/admin/media/upload", "POST", raw=b"")[0] == 422, "empty upload accepted"
        )
        check(
            admin.request("/admin/media/upload", "POST", raw=b"x" * (5 * 1024 * 1024 + 1))[0]
            == 413,
            "oversized upload accepted",
        )
        status, _, text = admin.request(
            "/admin/media/upload", "POST", raw=fixture, content_type="image/jpeg"
        )
        check(status == 201, "valid image upload: " + text[:250])
        media = json.loads(text)
        check(
            re.fullmatch(r"/media/[A-Za-z0-9_-]{32}\.jpg", media["url"]) is not None,
            "unsafe image URL",
        )
        check(
            media["width"] > 0 and media["height"] > 0 and media["size"] == len(fixture),
            "image metadata",
        )
        status, headers, payload = public.request(media["url"], binary=True)
        check(status == 200 and payload == fixture, "PublicHandler image bytes")
        check(
            headers.get("content-type") == "image/jpeg"
            and headers.get("x-content-type-options") == "nosniff",
            "image response type",
        )
        check(
            "set-cookie" not in headers and "immutable" in headers.get("cache-control", ""),
            "media route session or caching",
        )
        for path in [
            "/media/cms.sqlite",
            "/media/..%2Fcms.sqlite",
            "/media/.hidden.jpg",
            "/media/" + ("a" * 32) + ".jpg",
            "/storage/cms.sqlite",
        ]:
            check(public.request(path)[0] in (403, 404), "unsafe storage path exposed: " + path)
        mark(
            "Guarded image upload, size/type validation and session-free PublicHandler media serving"
        )
        data = {
            "id": "",
            "title": "Integration content item " + suffix + " & a <quiet> thought",
            "slug": slug,
            "excerpt": "A temporary content item used to verify publishing end to end.",
            "content": "## A working notebook\n\nThis content item checks persistent model creation, publishing, and safe rendering.\n\n![A quiet coastline]("
            + media["url"]
            + ')\n\n<script>alert("unsafe")</script>',
            "category": category_name,
            "image": "",
            "image_alt": "A calm coastline",
            "status": "draft",
            "published_at": "2026-11-03",
        }
        check(
            admin.request("/admin/content/save", "POST", {**data, "category": "Unknown " + suffix})[
                0
            ]
            == 422,
            "content item saved with an unregistered category",
        )
        check(admin.request("/admin/content/save", "POST", data)[0] == 303, "create draft")
        status, _, text = admin.request("/admin/content?q=" + slug)
        match = re.search(r"/admin/content/(\d+)/edit", text)
        check(status == 200 and match is not None, "created content item missing from collection")
        content_id = match.group(1)
        check(
            admin.request("/admin/categories/" + str(category_id) + "/delete", "POST", {})[0]
            == 422,
            "category with a draft was deleted",
        )
        _, _, payload = admin.request("/admin/categories", extra_headers=inertia_headers)
        check(
            next(
                value
                for value in json.loads(payload)["props"]["categoryList"]
                if value["id"] == category_id
            )["items"]
            == 1,
            "category counts exclude draft content",
        )
        check(public.request("/content/" + slug)[0] == 404, "created draft is public")
        status, _, payload = admin.request(
            "/admin/content/" + content_id + "/edit", extra_headers=inertia_headers
        )
        check(
            status == 200 and json.loads(payload)["props"]["item"]["image"] == "",
            "empty cover was replaced with a stock photo",
        )
        data.update(id=content_id, status="published", image=media["url"])
        check(admin.request("/admin/content/save", "POST", data)[0] == 303, "publish content item")
        status, _, text = public.request("/content/" + slug)
        check(
            status == 200 and ">A working notebook</h2>" in text,
            "published content item or Markdown",
        )
        check(
            "&lt;script&gt;" in text and "<script>alert(" not in text, "unsafe content item markup"
        )
        check(
            '<figure class="content-inline-image"><img src="'
            + media["url"]
            + '" alt="A quiet coastline"'
            in text,
            "uploaded inline image rendering",
        )
        check(
            'class="content-cover" src="' + media["url"] + '"' in text,
            "uploaded cover image rendering",
        )
        check(
            slug in public.request("/content?category=" + urllib.parse.quote(category_name))[2],
            "published category listing",
        )
        feed = ElementTree.fromstring(public.request("/rss.xml")[2])
        feed_item = next(
            item for item in feed.findall("./channel/item") if slug in item.findtext("link", "")
        )
        check(
            feed_item.findtext("title") == data["title"], "RSS XML text was not escaped correctly"
        )
        for invalid_date in ["not-a-date", "2026-11-XX"]:
            check(
                admin.request(
                    "/admin/content/save",
                    "POST",
                    {**data, "id": content_id, "published_at": invalid_date},
                )[0]
                == 422,
                "invalid site date did not render a validation error",
            )
        _, _, payload = admin.request(
            "/admin/content/" + content_id + "/edit", extra_headers=inertia_headers
        )
        before_rename = json.loads(payload)["props"]["item"]
        renamed_category = "Renamed " + suffix
        check(
            admin.request(
                "/admin/categories/save", "POST", {"id": category_id, "name": renamed_category}
            )[0]
            == 303,
            "rename an assigned category",
        )
        _, _, payload = admin.request(
            "/admin/content/" + content_id + "/edit", extra_headers=inertia_headers
        )
        after_rename = json.loads(payload)["props"]["item"]
        check(
            after_rename["category"] == renamed_category
            and after_rename["content"] == before_rename["content"]
            and after_rename["updated_at"] == before_rename["updated_at"],
            "category rename lost content item data or changed its edit date",
        )
        _, _, payload = public.request(
            "/content?category=" + urllib.parse.quote(renamed_category),
            extra_headers=inertia_headers,
        )
        renamed_page = json.loads(payload)
        check(
            any(item["slug"] == slug for item in renamed_page["props"]["items"]),
            "renamed category filter lost assigned content item",
        )
        check(
            category_name not in renamed_page["props"]["categories"]
            and renamed_category in renamed_page["props"]["categories"],
            "old category remains in public filters",
        )
        status, redirect, _ = admin.request(
            "/admin/categories/" + str(category_id) + "/delete",
            "POST",
            {},
            extra_headers=inertia_headers,
        )
        check(
            status == 303 and redirect.get("location") == "/admin/categories",
            "used category deletion error did not use Inertia redirect",
        )
        _, _, payload = admin.request("/admin/categories", extra_headers=inertia_headers)
        check(
            json.loads(payload)["props"]["errors"].get("category"),
            "used category deletion error is missing",
        )
        data["category"] = renamed_category
        mark(
            "Atomic category rename, preserved content, live public filters and used-category deletion protection"
        )
        bad = dict(data, slug="welcome-to-haxepress")
        check(
            admin.request("/admin/content/save", "POST", bad)[0] == 422, "duplicate slug accepted"
        )
        status, redirect, _ = admin.request(
            "/admin/content/save", "POST", bad, extra_headers=inertia_headers
        )
        check(
            status == 303 and redirect.get("location") == "/admin/content/" + content_id + "/edit",
            "Inertia validation redirect",
        )
        status, _, payload = admin.request(redirect["location"], extra_headers=inertia_headers)
        validation = json.loads(payload)
        check(
            status == 200
            and validation["component"] == "Admin/Editor"
            and validation["props"]["errors"].get("content"),
            "Inertia validation errors",
        )
        check(
            "password" not in validation["props"]["auth"]["admin"],
            "private admin password leaked in props",
        )
        for image in [
            "https://example.com/cover.jpg",
            "//example.com/cover.jpg",
            "/images/coast.jpg",
            "/media/" + ("a" * 32) + ".jpg",
        ]:
            check(
                admin.request("/admin/content/save", "POST", {**data, "image": image})[0] == 422,
                "non-uploaded cover accepted: " + image,
            )
        for image in [
            "https://example.com/content.jpg",
            "//example.com/content.jpg",
            "/images/coast.jpg",
            "/media/" + ("b" * 32) + ".jpg",
        ]:
            check(
                admin.request(
                    "/admin/content/save",
                    "POST",
                    {**data, "content": data["content"] + "\n\n![Unmanaged image](" + image + ")"},
                )[0]
                == 422,
                "non-uploaded content item image accepted: " + image,
            )
        check(
            admin.request("/admin/content/save", "POST", {**data, "image": ""})[0] == 303,
            "remove cover reference",
        )
        status, _, empty_cover_page = public.request("/content/" + slug)
        check(
            status == 200
            and 'class="content-cover"' not in empty_cover_page
            and 'class="content-inline-image"' in empty_cover_page,
            "content item without a cover uses a stock photo or loses inline images",
        )
        data["image"] = ""
        mark("Upload-only covers and Markdown images, empty covers, and legacy image import")
        mark("Eloquent draft creation, update, publishing, Markdown, XSS escaping and unique slugs")
        _, _, payload = public.request("/", extra_headers=inertia_headers)
        featured_id = json.loads(payload)["props"]["featured"]["id"]
        _, _, payload = admin.request(
            "/admin/content/" + str(featured_id) + "/edit", extra_headers=inertia_headers
        )
        original_featured = json.loads(payload)["props"]["item"]
        data["featured"] = "1"
        check(
            admin.request("/admin/content/save", "POST", data)[0] == 303,
            "feature the cached content item",
        )
        _, _, payload = public.request("/", extra_headers=inertia_headers)
        check(
            str(json.loads(payload)["props"]["featured"]["id"]) == content_id,
            "featured homepage cache is stale",
        )
        data["status"] = "draft"
        check(
            admin.request("/admin/content/save", "POST", data)[0] == 303,
            "unpublish the cached content item",
        )
        check(
            public.request("/content/" + slug)[0] == 404
            and slug not in public.request("/rss.xml")[2],
            "unpublished cached content item remains public",
        )
        _, _, payload = public.request("/content", extra_headers=inertia_headers)
        check(
            all(item["slug"] != slug for item in json.loads(payload)["props"]["items"]),
            "unpublished content item remains in cached lists",
        )
        data["status"] = "published"
        previous_slug = slug
        slug += "-revised"
        data["slug"] = slug
        check(
            admin.request("/admin/content/save", "POST", data)[0] == 303,
            "republish with a new slug",
        )
        check(
            public.request("/content/" + previous_slug)[0] == 404
            and public.request("/content/" + slug)[0] == 200,
            "old or new content item slug cache is stale",
        )
        _, _, payload = public.request("/", extra_headers=inertia_headers)
        check(
            json.loads(payload)["props"]["featured"]["slug"] == slug
            and slug in public.request("/rss.xml")[2],
            "republished homepage or RSS cache is stale",
        )
        mark(
            "Immediate cache invalidation for featuring, unpublishing, republishing and slug changes"
        )
        status, headers, _ = public.request("/subscribe", "POST", {"email": email}, csrf=False)
        check(
            status == 200 and "set-cookie" not in headers,
            "newsletter signup must stay session-free",
        )
        check(public.request("/subscribe", "POST", {"email": email})[0] == 200, "idempotent signup")
        with ThreadPoolExecutor(max_workers=6) as pool:
            statuses = list(
                pool.map(
                    lambda _: Client().request("/subscribe", "POST", {"email": email}, csrf=False)[
                        0
                    ],
                    range(6),
                )
            )
        check(statuses == [200] * 6, "duplicate subscription requests need no transaction")
        status, _, text = admin.request("/admin/subscribers")
        check(
            status == 200 and text.count("<strong>" + email + "</strong>") == 1,
            "subscriber deduplication",
        )
        row = re.search(
            r"<tr><td><strong>" + re.escape(email) + r"</strong>.*?/admin/subscribers/(\d+)/delete",
            text,
            re.S,
        )
        check(row is not None, "subscriber management row")
        subscriber_id = row.group(1)
        status, headers, text = admin.request("/admin/subscribers/export")
        check(status == 200 and "text/csv" in headers.get("content-type", ""), "CSV export type")
        check(
            sum(1 for row in csv.reader(io.StringIO(text)) if row and row[0] == email) == 1,
            "CSV export content",
        )
        mark("Persistent Eloquent newsletter signup, deduplication, management and CSV export")
        _, _, payload = admin.request("/admin/settings", extra_headers=inertia_headers)
        original_settings = json.loads(payload)["props"]["site"]
        updated_settings = {**original_settings, "site_name": "HaxePress " + suffix}
        try:
            check(
                admin.request("/admin/settings", "POST", updated_settings)[0] == 303,
                "save cached site settings",
            )
            _, _, payload = public.request("/", extra_headers=inertia_headers)
            check(
                json.loads(payload)["props"]["site"]["site_name"] == updated_settings["site_name"],
                "public settings cache is stale",
            )
            check(
                updated_settings["site_name"] in public.request("/rss.xml")[2],
                "RSS settings cache is stale",
            )
            check(
                admin.request("/admin/settings", "POST", {**updated_settings, "site_name": ""})[0]
                == 422,
                "invalid settings accepted",
            )
            _, _, payload = public.request("/about", extra_headers=inertia_headers)
            check(
                json.loads(payload)["props"]["site"]["site_name"] == updated_settings["site_name"],
                "failed settings update changed cached content",
            )
        finally:
            check(
                admin.request("/admin/settings", "POST", original_settings)[0] == 303,
                "restore site settings",
            )
        _, _, payload = public.request("/", extra_headers=inertia_headers)
        check(
            json.loads(payload)["props"]["site"]["site_name"] == original_settings["site_name"],
            "restored settings cache is stale",
        )
        mark("Site settings and RSS caches refresh after a successful save")
        check(
            admin.request("/admin/content/" + content_id + "/delete", "POST", {})[0] == 303,
            "delete content item",
        )
        content_id = None
        check(public.request("/content/" + slug)[0] == 404, "deleted content item still public")
        restored = {
            key: original_featured.get(key, "")
            for key in [
                "id",
                "title",
                "slug",
                "excerpt",
                "content",
                "category",
                "image",
                "image_alt",
                "status",
            ]
        }
        restored.update(featured="1", published_at=original_featured["published_at"][:10])
        check(
            admin.request("/admin/content/save", "POST", restored)[0] == 303,
            "restore the original featured content item",
        )
        original_featured = None
        check(
            admin.request("/admin/categories/" + str(category_id) + "/delete", "POST", {})[0]
            == 303,
            "delete unused category",
        )
        category_id = None
        _, _, payload = public.request("/content", extra_headers=inertia_headers)
        check(
            renamed_category not in json.loads(payload)["props"]["categories"],
            "deleted category remains in public filters",
        )
        mark("Unused category deletion and refreshed public category choices")
        check(
            admin.request("/admin/subscribers/" + subscriber_id + "/delete", "POST", {})[0] == 303,
            "delete subscriber",
        )
        subscriber_id = None
        mark("Eloquent content item and subscriber deletion")
        old_cookies = dict(admin.cookies)
        check(admin.request("/admin/logout", "POST", {})[0] == 303, "logout")
        check(admin.request("/admin")[0] == 303, "logged-out access")
        replay = Client()
        replay.cookies = old_cookies
        check(replay.request("/admin")[0] == 303, "old session cookie remains valid")
        mark("Logout and rejection of a replayed previous session")
    finally:
        if not content_id and admin.csrf:
            _, _, text = admin.request(
                "/admin/content?q=" + urllib.parse.quote("Integration content item " + suffix)
            )
            match = re.search(r"/admin/content/(\d+)/edit", text)
            if match:
                content_id = match.group(1)
        if content_id:
            admin.request("/admin/content/" + content_id + "/delete", "POST", {})
        if original_featured:
            restored = {
                key: original_featured.get(key, "")
                for key in [
                    "id",
                    "title",
                    "slug",
                    "excerpt",
                    "content",
                    "category",
                    "image",
                    "image_alt",
                    "status",
                ]
            }
            restored.update(featured="1", published_at=original_featured["published_at"][:10])
            admin.request("/admin/content/save", "POST", restored)
        if category_id:
            admin.request("/admin/categories/" + str(category_id) + "/delete", "POST", {})
        if subscriber_id:
            admin.request("/admin/subscribers/" + subscriber_id + "/delete", "POST", {})
    print(str(len(passed)) + " integration checks passed.", flush=True)


if __name__ == "__main__":
    run()
