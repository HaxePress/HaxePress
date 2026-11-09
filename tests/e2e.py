#!/usr/bin/env python3
"""Exercise the running HxWell/Crossbyte app through real HTTP requests.

Creates and removes only uniquely named test content, categories, and subscribers.
Signs in with TEST_ADMIN_EMAIL / TEST_ADMIN_PASSWORD; .env keeps no administrator credentials.
"""

import csv
import hashlib
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
            headers["Cookie"] = "; ".join(f"{key}={value}" for key, value in self.cookies.items())
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
                    f"{normalized[name]}, {value}"
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
            if not binary and normalized.get("x-well-data") == "true":
                page = json.loads(text)
                if page.get("props", {}).get("csrfToken"):
                    self.csrf = page["props"]["csrfToken"]
            return response.status, normalized, text
        finally:
            connection.close()

    def verify_image(self, path, upload_id, digest, dimensions, csrf=True):
        width, height = dimensions
        return self.request(
            f"{path}/verify",
            "POST",
            raw=json.dumps(
                {"id": upload_id, "sha256": digest, "width": width, "height": height}
            ).encode(),
            content_type="application/json",
            csrf=csrf,
        )

    def delete_media(self, media_id):
        """Deletes an image as a person does: into the trash, then permanently."""
        self.request(f"/admin/media/{str(media_id)}/trash", "POST", {})
        return self.request(f"/admin/media/{str(media_id)}/permanent-delete", "POST", {})

    def upload_image(self, path, raw, content_type, dimensions, extra_headers=None):
        status, headers, payload = self.request(
            path,
            "POST",
            raw=raw,
            content_type=content_type,
            binary=True,
            extra_headers=extra_headers,
        )
        if status != 202:
            return status, headers, payload.decode("utf-8")
        check(payload == raw, "Staged image bytes differ from the selected file")
        return self.verify_image(
            path, headers["x-upload-id"], hashlib.sha256(payload).hexdigest(), dimensions
        )


def check(condition, message):
    if not condition:
        raise AssertionError(message)


DATA_HEADERS = {"X-Well-Data": "true", "Accept": "application/json"}


class IslandParser(HTMLParser):
    """Collects the typed props of each `<well-island>` in server-rendered HTML."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.islands = {}
        self.names = []
        self.reading = None

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "well-island":
            self.names.append(values.get("data-name", ""))
        elif tag == "script" and "data-well-props" in values and self.names:
            self.reading = []

    def handle_endtag(self, tag):
        if tag == "well-island" and self.names:
            self.names.pop()
        elif tag == "script" and self.reading is not None:
            self.islands[self.names[-1]] = json.loads("".join(self.reading))
            self.reading = None

    def handle_data(self, data):
        if self.reading is not None:
            self.reading.append(data)


def island_props(text, name):
    parser = IslandParser()
    parser.feed(text)
    island = parser.islands.get(name)
    return None if island is None else island["props"]


def run():
    public = Client()
    admin = Client()
    passed = []
    content_id = None
    subscriber_id = None
    category_id = None
    original_featured = None
    suffix = uuid.uuid4().hex[:12]
    slug = f"integration-content-{suffix}"
    email = f"integration-{suffix}@example.com"

    def mark(name):
        passed.append(name)
        print(f"PASS {name}", flush=True)

    try:
        status, headers, text = public.request("/")
        check(status == 200 and "The latest content" in text, "home page")
        check("::" not in text, "unresolved Haxe template data")
        check(headers.get("x-content-type-options") == "nosniff", "security headers")
        # Scripts run only from the site or with this response's nonce, so injected markup cannot run.
        policy = headers.get("content-security-policy", "")
        scripts = next(
            (part.strip() for part in policy.split(";") if part.strip().startswith("script-src")),
            "",
        )
        nonce = re.search(r"'nonce-([A-Za-z0-9_-]+)'", scripts)
        check(
            nonce is not None
            and "'unsafe-inline'" not in scripts
            and f'nonce="{nonce.group(1)}"' in text
            and "object-src 'none'" in policy
            and "frame-ancestors 'none'" in policy,
            f"content security policy: {policy}",
        )
        # Fonts download with the stylesheets, so text is not first drawn in a fallback font.
        head = text.split("</head>", 1)[0]
        font_preloads = re.findall(
            r'<link rel="preload" href="(/build/assets/[^"]+\.woff2)" as="font" '
            r'type="font/woff2" crossorigin>',
            head,
        )
        first_stylesheet = head.find('rel="stylesheet"')
        check(
            font_preloads and all(head.find(url) < first_stylesheet for url in font_preloads),
            f"font preloads come before the stylesheets: {font_preloads}",
        )
        status, font_headers, _ = public.request(font_preloads[0], binary=True)
        check(
            status == 200
            and font_headers.get("content-type") == "font/woff2"
            and "immutable" in font_headers.get("cache-control", ""),
            f"built assets are cached for a year: {font_headers.get('cache-control')!r}",
        )
        check(
            "set-cookie" not in headers and not public.cookies, "public homepage creates a session"
        )
        check(
            "<main" in text
            and "data-cms-site" in text
            and "data-page=" not in text
            and 'id="app"' not in text,
            "homepage was not rendered as server HTML without a client hydration root",
        )
        check(
            "well-fragment" in headers.get("vary", "").lower(),
            f"fragment Vary header: vary={headers.get('vary')!r}",
        )
        status, home_headers, payload = public.request("/", extra_headers=DATA_HEADERS)
        home = json.loads(payload)
        check(
            status == 200
            and home_headers.get("x-well-data") == "true"
            and home["component"] == "Home",
            "homepage page data",
        )
        check(isinstance(home["props"]["items"], list), "HTML strings were not replaced with props")
        covers = [home["props"]["featured"], *home["props"]["items"]]
        check(
            all(item["image"].startswith("/media/") for item in covers),
            "existing site covers were not moved into upload storage",
        )
        rendered_text = html.unescape(text)
        check(
            all(item["title"] in rendered_text for item in covers),
            "server HTML is missing homepage content from its page data",
        )
        stylesheet = re.search(r'<link rel="stylesheet" href="(/build/[^\"]+)"', text)
        check(stylesheet is not None, "Vite stylesheet is missing")
        mark("English server-rendered HTML, page data, Vite assets, and response headers")
        status, data_headers, payload = public.request(
            "/content?category=Getting%20started", extra_headers=DATA_HEADERS
        )
        check(
            status == 200,
            f"page data status={status}, headers={data_headers}, body={payload[:150]!r}",
        )
        check(
            data_headers.get("x-well-data") == "true",
            f"page data header missing: headers={data_headers}, body={payload[:180]!r}",
        )
        page = json.loads(payload)
        check(page["component"] == "ContentIndex", "content index page data")
        check(
            len(page["props"]["items"]) == 1 and "category=Getting%20started" in page["url"],
            "page-data props and query-string URL",
        )
        check(
            page["props"].get("auth") is None
            and page["props"].get("csrfToken") is None
            and "set-cookie" not in data_headers,
            "public page-data session isolation",
        )
        status, fallback_headers, fallback = public.request(
            "/content?category=Getting%20started", extra_headers={"Well-Fragment": "missing"}
        )
        check(
            status == 200
            and "well-fragment" not in fallback_headers
            and "<html" in fallback
            and "Create and organize content" in fallback
            and "set-cookie" not in fallback_headers,
            "unknown fragment request did not fall back to the full session-free page",
        )
        mark("Page data, fragment fallback, and stateless public props")
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
                f"public route or asset creates sessions: {path}",
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
                f"unprotected admin route: {path}",
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
                f"unprotected category write: {path}",
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
                "email": os.environ["TEST_ADMIN_EMAIL"],
                "password": os.environ["TEST_ADMIN_PASSWORD"],
            },
        )
        check(status == 303 and headers.get("location") == "/admin", "admin login")
        status, headers, text = admin.request("/admin")
        check(
            status == 200
            and "<h1>Overview</h1>" in text
            and 'action="/admin/logout"' in text
            and headers.get("cache-control") == "private, no-store",
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
            check(page_status == 200 and "::" not in page, f"authenticated page rendering: {path}")
            if path == "/admin/content/new":
                check(
                    "Cover image URL" not in page and 'id="cover-url"' not in page,
                    "manual cover URL field remains",
                )
                editor = island_props(page, "content-editor")
                check(
                    editor is not None and editor["editor"]["item"]["image"] == "",
                    "new content should not have an automatic stock cover",
                )
                check(
                    "image" in editor["editor"]["contentType"]["features"]
                    and editor["editor"]["mediaRules"]["uploadUrl"] == "/admin/media/upload",
                    "empty upload-only cover state",
                )
        status, headers, fragment = admin.request(
            "/admin/media", extra_headers={"Well-Fragment": "media-workspace"}
        )
        check(
            status == 200
            and headers.get("well-fragment") == "media-workspace"
            and fragment.startswith(
                '<div class="media-workspace" data-well-fragment="media-workspace">'
            )
            and "<html" not in fragment
            and "<nav" not in fragment
            and headers.get("cache-control") == "private, no-store",
            "fragment request did not return only the requested fragment",
        )
        mark(
            (
                "HxWell admin auth guard and regenerated session ("
                f"{str(round(time.monotonic() - start, 2))}s)"
            )
        )
        category_name = f"Integration {suffix}"
        check(
            admin.request(
                "/admin/categories/save", "POST", {"id": "", "name": f"  {category_name}  "}
            )[0]
            == 303,
            "create category",
        )
        status, _, payload = admin.request("/admin/categories", extra_headers=DATA_HEADERS)
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
        _, _, public_categories = public.request("/content", extra_headers=DATA_HEADERS)
        check(
            category_name in json.loads(public_categories)["props"]["categories"],
            "public categories are not database-backed",
        )
        for name in ["", "x" * 81, category_name.upper()]:
            check(
                admin.request("/admin/categories/save", "POST", {"id": "", "name": name})[0] == 422,
                f"invalid or duplicate category accepted: {name}",
            )
        status, redirect, _ = admin.request(
            "/admin/categories/save",
            "POST",
            {"id": "", "name": category_name.upper()},
            extra_headers=DATA_HEADERS,
        )
        check(
            status == 303 and redirect.get("location") == "/admin/categories",
            "page-data category validation redirect",
        )
        status, _, payload = admin.request("/admin/categories", extra_headers=DATA_HEADERS)
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
            admin.request(f"/admin/categories/{str(category_id)}/delete", "POST", {}, csrf=False)[0]
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
            admin.request("/admin/media/upload", "POST", raw=b"")[0] == 422, "empty upload accepted"
        )
        check(
            admin.request("/admin/media/upload", "POST", raw=b"x" * (5 * 1024 * 1024 + 1))[0]
            == 413,
            "oversized upload accepted",
        )
        upload = "/admin/media/upload"
        status, headers, payload = admin.request(
            upload, "POST", raw=fixture, content_type="image/jpeg", binary=True
        )
        check(status == 202 and payload == fixture, "Staged image bytes changed")
        check(
            headers.get("content-type") == "image/jpeg"
            and headers.get("cache-control") == "private, no-store",
            "Staged image type or caching",
        )
        upload_id = headers["x-upload-id"]
        dimensions = (1000, 750)
        digest = hashlib.sha256(fixture).hexdigest()
        check(
            admin.verify_image(upload, upload_id, digest, dimensions, csrf=False)[0] == 419,
            "Image confirmation bypassed CSRF",
        )
        other_session = Client()
        other_session.request("/admin/login")
        status, headers, _ = other_session.request(
            "/admin/login",
            "POST",
            {
                "email": os.environ["TEST_ADMIN_EMAIL"],
                "password": os.environ["TEST_ADMIN_PASSWORD"],
            },
        )
        check(status == 303 and headers.get("location") == "/admin", "Second admin login")
        other_session.request("/admin")
        check(
            other_session.verify_image(upload, upload_id, digest, dimensions)[0] == 404,
            "A separate admin session confirmed the upload",
        )
        other_session.request("/admin/logout", "POST", {})
        wrong_digest = hashlib.sha256(b"different image").hexdigest()
        check(
            admin.verify_image(upload, upload_id, wrong_digest, dimensions)[0] == 422,
            "Image confirmation accepted a mismatched hash",
        )
        status, _, text = admin.verify_image(upload, upload_id, digest, dimensions)
        check(status == 201, f"Valid image confirmation: {text[:250]}")
        check(
            admin.verify_image(upload, upload_id, digest, dimensions)[0] == 404,
            "A confirmed upload ID was reused",
        )
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
            f"/media/{'a' * 32}.jpg",
            "/storage/cms.sqlite",
            # Shipped plugin and theme archives live outside the web root and are never served.
            "/packages/rss-2.16.0.zip",
            "/packages/notebook-2.16.0.zip",
            "/packages/cms-plugin-api-4.jar",
            "/private/packages/rss-2.16.0.zip",
            "/private/seeds/seed.json",
            "/private/database/cms.sqlite",
        ]:
            check(public.request(path)[0] in (403, 404), f"unsafe storage path exposed: {path}")
        # A missing image gets the site's own 404 page, like any other missing page.
        status, _, missing = public.request(f"/media/{'b' * 32}.png")
        check(
            status == 404 and "<html" in missing and "Image not found." not in missing,
            f"a missing image did not get the site's 404 page: {missing[:120]!r}",
        )
        mark(
            "Private image staging, session-bound hash confirmation and PublicHandler media serving"
        )
        data = {
            "id": "",
            "title": f"Integration content item {suffix} & a <quiet> thought",
            "slug": slug,
            "excerpt": "A temporary content item used to verify publishing end to end.",
            "content": (
                "## A working notebook\n\nThis content item checks persistent model creation, publishing, and safe rendering.\n\n![A quiet coastline]("
                f"""{media['url']})\n\n<script>alert("unsafe")</script>"""
            ),
            "category": category_name,
            "image": "",
            "image_alt": "A calm coastline",
            "status": "draft",
            "published_at": "2026-11-03",
        }
        check(
            admin.request("/admin/content/save", "POST", {**data, "category": f"Unknown {suffix}"})[
                0
            ]
            == 422,
            "content item saved with an unregistered category",
        )
        check(admin.request("/admin/content/save", "POST", data)[0] == 303, "create draft")
        status, _, text = admin.request(f"/admin/content?q={slug}")
        match = re.search(r"/admin/content/(\d+)/edit", text)
        check(status == 200 and match is not None, "created content item missing from collection")
        content_id = match.group(1)
        check(
            admin.request(f"/admin/categories/{str(category_id)}/delete", "POST", {})[0] == 422,
            "category with a draft was deleted",
        )
        _, _, payload = admin.request("/admin/categories", extra_headers=DATA_HEADERS)
        check(
            next(
                value
                for value in json.loads(payload)["props"]["categoryList"]
                if value["id"] == category_id
            )["items"]
            == 1,
            "category counts exclude draft content",
        )
        check(public.request(f"/content/{slug}")[0] == 404, "created draft is public")
        status, _, payload = admin.request(
            f"/admin/content/{content_id}/edit", extra_headers=DATA_HEADERS
        )
        check(
            status == 200 and json.loads(payload)["props"]["item"]["image"] == "",
            "empty cover was replaced with a stock photo",
        )
        data.update(id=content_id, status="published", image=media["url"])
        check(admin.request("/admin/content/save", "POST", data)[0] == 303, "publish content item")
        status, _, text = public.request(f"/content/{slug}")
        check(
            status == 200 and ">A working notebook</h2>" in text,
            "published content item or Markdown",
        )
        check(
            "&lt;script&gt;" in text and "<script>alert(" not in text, "unsafe content item markup"
        )
        check(
            (
                f"""<figure class="content-inline-image"><img src="{media['url']}"""
                '" alt="A quiet coastline"'
            )
            in text,
            "uploaded inline image rendering",
        )
        check(
            f'''class="content-cover" src="{media['url']}"''' in text,
            "uploaded cover image rendering",
        )
        check(
            slug in public.request(f"/content?category={urllib.parse.quote(category_name)}")[2],
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
            f"/admin/content/{content_id}/edit", extra_headers=DATA_HEADERS
        )
        before_rename = json.loads(payload)["props"]["item"]
        renamed_category = f"Renamed {suffix}"
        check(
            admin.request(
                "/admin/categories/save", "POST", {"id": category_id, "name": renamed_category}
            )[0]
            == 303,
            "rename an assigned category",
        )
        _, _, payload = admin.request(
            f"/admin/content/{content_id}/edit", extra_headers=DATA_HEADERS
        )
        after_rename = json.loads(payload)["props"]["item"]
        check(
            after_rename["category"] == renamed_category
            and after_rename["content"] == before_rename["content"]
            and after_rename["updated_at"] == before_rename["updated_at"],
            "category rename lost content item data or changed its edit date",
        )
        _, _, payload = public.request(
            f"/content?category={urllib.parse.quote(renamed_category)}",
            extra_headers=DATA_HEADERS,
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
            f"/admin/categories/{str(category_id)}/delete",
            "POST",
            {},
            extra_headers=DATA_HEADERS,
        )
        check(
            status == 303 and redirect.get("location") == "/admin/categories",
            "used category deletion error did not redirect back",
        )
        _, _, payload = admin.request("/admin/categories", extra_headers=DATA_HEADERS)
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
            "/admin/content/save", "POST", bad, extra_headers=DATA_HEADERS
        )
        check(
            status == 303 and redirect.get("location") == f"/admin/content/{content_id}/edit",
            "page-data validation redirect",
        )
        status, _, payload = admin.request(redirect["location"], extra_headers=DATA_HEADERS)
        validation = json.loads(payload)
        check(
            status == 200
            and validation["component"] == "Admin/Editor"
            and validation["props"]["errors"].get("content"),
            "page-data validation errors",
        )
        check(
            "password" not in validation["props"]["auth"]["admin"],
            "private admin password leaked in props",
        )
        for image in [
            "https://example.com/cover.jpg",
            "//example.com/cover.jpg",
            "/images/coast.jpg",
            f"/media/{'a' * 32}.jpg",
        ]:
            check(
                admin.request("/admin/content/save", "POST", {**data, "image": image})[0] == 422,
                f"non-uploaded cover accepted: {image}",
            )
        for image in [
            "https://example.com/content.jpg",
            "//example.com/content.jpg",
            "/images/coast.jpg",
            f"/media/{'b' * 32}.jpg",
        ]:
            check(
                admin.request(
                    "/admin/content/save",
                    "POST",
                    {**data, "content": f"{data['content']}\n\n![Unmanaged image]({image})"},
                )[0]
                == 422,
                f"non-uploaded content item image accepted: {image}",
            )
        check(
            admin.request("/admin/content/save", "POST", {**data, "image": ""})[0] == 303,
            "remove cover reference",
        )
        status, _, empty_cover_page = public.request(f"/content/{slug}")
        check(
            status == 200
            and 'class="content-cover"' not in empty_cover_page
            and 'class="content-inline-image"' in empty_cover_page,
            "content item without a cover uses a stock photo or loses inline images",
        )
        data["image"] = ""
        mark("Upload-only covers and Markdown images, empty covers, and legacy image import")
        mark("Eloquent draft creation, update, publishing, Markdown, XSS escaping and unique slugs")
        _, _, payload = public.request("/", extra_headers=DATA_HEADERS)
        featured_id = json.loads(payload)["props"]["featured"]["id"]
        _, _, payload = admin.request(
            f"/admin/content/{str(featured_id)}/edit", extra_headers=DATA_HEADERS
        )
        original_featured = json.loads(payload)["props"]["item"]
        data["featured"] = "1"
        check(
            admin.request("/admin/content/save", "POST", data)[0] == 303,
            "feature the cached content item",
        )
        _, _, payload = public.request("/", extra_headers=DATA_HEADERS)
        check(
            str(json.loads(payload)["props"]["featured"]["id"]) == content_id,
            "featured homepage cache is stale",
        )
        # The administration marks the featured item in Recent content and in the content list.
        for page in ["/admin", "/admin/content"]:
            rows = [row.split("</tr>", 1)[0] for row in admin.request(page)[2].split("<tr>")]
            featured_row = next((row for row in rows if f"/{content_id}/edit" in row), "")
            check(
                'class="featured-text"' in featured_row,
                f"{page} does not mark the featured content item",
            )
        data["status"] = "draft"
        check(
            admin.request("/admin/content/save", "POST", data)[0] == 303,
            "unpublish the cached content item",
        )
        check(
            public.request(f"/content/{slug}")[0] == 404
            and slug not in public.request("/rss.xml")[2],
            "unpublished cached content item remains public",
        )
        _, _, payload = public.request("/content", extra_headers=DATA_HEADERS)
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
            public.request(f"/content/{previous_slug}")[0] == 404
            and public.request(f"/content/{slug}")[0] == 200,
            "old or new content item slug cache is stale",
        )
        _, _, payload = public.request("/", extra_headers=DATA_HEADERS)
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
            status == 200 and text.count(f"<strong>{email}</strong>") == 1,
            "subscriber deduplication",
        )
        row = re.search(
            f"<tr><td><strong>{re.escape(email)}</strong>.*?/admin/subscribers/(\\d+)/delete",
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
        formula = f"+csv-{suffix}@example.test"
        check(
            public.request("/subscribe", "POST", {"email": formula}, csrf=False)[0] == 200,
            "a subscription that starts like a formula",
        )
        _, _, text = admin.request("/admin/subscribers/export")
        exported = [row[0] for row in csv.reader(io.StringIO(text)) if row and formula in row[0]]
        check(exported == [f"'{formula}"], f"CSV export kept a formula as a formula: {exported}")
        mark("Persistent Eloquent newsletter signup, deduplication, management and CSV export")
        _, _, payload = admin.request("/admin/settings", extra_headers=DATA_HEADERS)
        original_settings = json.loads(payload)["props"]["site"]
        updated_settings = {**original_settings, "site_name": f"HaxePress {suffix}"}
        try:
            check(
                admin.request("/admin/settings", "POST", updated_settings)[0] == 303,
                "save cached site settings",
            )
            _, _, payload = public.request("/", extra_headers=DATA_HEADERS)
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
            _, _, payload = public.request("/about", extra_headers=DATA_HEADERS)
            check(
                json.loads(payload)["props"]["site"]["site_name"] == updated_settings["site_name"],
                "failed settings update changed cached content",
            )
        finally:
            check(
                admin.request("/admin/settings", "POST", original_settings)[0] == 303,
                "restore site settings",
            )
        _, _, payload = public.request("/", extra_headers=DATA_HEADERS)
        check(
            json.loads(payload)["props"]["site"]["site_name"] == original_settings["site_name"],
            "restored settings cache is stale",
        )
        mark("Site settings and RSS caches refresh after a successful save")
        check(
            admin.request(f"/admin/content/{content_id}/delete", "POST", {})[0] == 303,
            "delete content item",
        )
        content_id = None
        check(public.request(f"/content/{slug}")[0] == 404, "deleted content item still public")
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
            admin.request(f"/admin/categories/{str(category_id)}/delete", "POST", {})[0] == 303,
            "delete unused category",
        )
        category_id = None
        _, _, payload = public.request("/content", extra_headers=DATA_HEADERS)
        check(
            renamed_category not in json.loads(payload)["props"]["categories"],
            "deleted category remains in public filters",
        )
        mark("Unused category deletion and refreshed public category choices")
        check(
            admin.request(f"/admin/subscribers/{subscriber_id}/delete", "POST", {})[0] == 303,
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
                f"/admin/content?q={urllib.parse.quote(f'Integration content item {suffix}')}"
            )
            match = re.search(r"/admin/content/(\d+)/edit", text)
            if match:
                content_id = match.group(1)
        if content_id:
            admin.request(f"/admin/content/{content_id}/delete", "POST", {})
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
            admin.request(f"/admin/categories/{str(category_id)}/delete", "POST", {})
        if subscriber_id:
            admin.request(f"/admin/subscribers/{subscriber_id}/delete", "POST", {})
    print(f"{str(len(passed))} integration checks passed.", flush=True)


if __name__ == "__main__":
    run()
