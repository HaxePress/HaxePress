"""Exercise content editing, working copies, revisions, schedules and media protection."""

import json
import os
from pathlib import Path
import re
import secrets
import time

from e2e import Client, check
from fixture_store import FixtureStore

ROOT = Path(__file__).resolve().parents[1]
HEADERS = {"X-Well-Data": "true", "Accept": "application/json"}


def props(client, path):
    status, _, body = client.request(path, extra_headers=HEADERS)
    check(status == 200, f"{path} returned {str(status)}: {body[:200]}")
    return json.loads(body)["props"]


def save(admin, kind, data):
    status, headers, body = admin.request(f"/admin/{kind}/save", "POST", data)
    check(status == 303, f"content save returned {str(status)}: {body[:300]}")
    return headers["location"]


def run():
    with FixtureStore.from_environment() as fixtures:
        verify(fixtures)


def verify(fixtures):
    admin = Client()
    public = Client()
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
        "content owner login",
    )
    suffix = secrets.token_hex(5)
    initial = props(admin, "/admin/pages/new")
    data = {
        "id": "",
        "title": "A permanent CMS page",
        "slug": f"cms-page-{suffix}",
        "excerpt": "",
        "content": "## A useful page\n\nA complete page with **bold** and *italic* text.\n\n| Place | Note |\n| --- | --- |\n| Home | Calm |\n\n- [x] Published thoughtfully\n\n<script>alert('unsafe')</script>",
        "category": "",
        "image": "",
        "image_alt": "",
        "status": "draft",
        "featured": "0",
        "published_at": "2026-11-03",
        "version": "1",
        "draft_key": initial["draftKey"],
        "tags": "",
        "stay": "1",
        "seo_title": "A page for curious readers",
        "seo_description": "A specific search description.",
    }
    preview_status, _, preview_html = admin.request("/admin/pages/preview", "POST", data)
    check(
        preview_status == 200
        and "data-cms-site" in preview_html
        and "<em>italic</em>" in preview_html,
        "A new page did not render in the site layout before saving",
    )
    check(
        public.request(f"/pages/{data['slug']}")[0] == 404,
        "Preview published a new page",
    )
    working = {**data, "draft_version": "1"}
    check(
        admin.request("/admin/pages/working-copy", "POST", working)[0] == 200,
        "save new-page working copy",
    )
    restored = props(admin, f"/admin/pages/new?draft={initial['draftKey']}")
    check(
        restored["workingCopy"]["data"]["content"] == data["content"],
        "new-page working copy did not restore",
    )
    location = save(admin, "pages", data)
    page_id = int(re.search(r"/pages/(\d+)/edit", location).group(1))
    data["id"] = str(page_id)
    check(
        admin.request("/admin/pages/working-copy", "POST", {**working, "draft_version": "2"})[0]
        == 422,
        "late autosave recreated a consumed new working copy",
    )
    check(public.request(f"/pages/{data['slug']}")[0] == 404, "draft page became public")
    check(
        public.request(f"/content/{data['slug']}")[0] == 404,
        "page leaked into content item routing",
    )
    editor = props(admin, f"/admin/pages/{str(page_id)}/edit")
    data["version"] = str(editor["item"]["version"])
    data["status"] = "published"
    save(admin, "pages", data)
    status, _, html = public.request(f"/pages/{data['slug']}")
    check(
        status == 200
        and "<table" in html
        and "<em>italic</em>" in html
        and 'type="checkbox"' in html,
        "GFM content was not rendered",
    )
    check("&lt;script&gt;" in html and "<script>alert(" not in html, "raw HTML executed")
    check(
        "A page for curious readers" in html and "A specific search description." in html,
        "page SEO fields were ignored",
    )
    check(
        re.search(r"<title[^>]*>A page for curious readers</title>", html),
        "custom SEO title was changed",
    )
    check(
        all(item["id"] != page_id for item in props(public, "/content")["items"]),
        "pages entered content",
    )

    history_status, _, history_body = admin.request(f"/admin/pages/{str(page_id)}/history")
    history = json.loads(history_body)["revisions"]
    check(
        history_status == 200 and [row["version"] for row in history] == [2, 1],
        "manual saves did not create revisions",
    )
    check(
        admin.request("/admin/pages/save", "POST", {**data, "version": "1"})[0] == 409,
        "stale editor overwrote content",
    )
    current = props(admin, f"/admin/pages/{str(page_id)}/edit")["item"]
    data["version"] = str(current["version"])
    data["content"] = "## An updated working copy\n\nThis should stay private until manually saved."
    check(
        admin.request("/admin/pages/working-copy", "POST", {**data, "draft_version": "5"})[0]
        == 200,
        "save existing working copy",
    )
    check(
        admin.request(
            "/admin/pages/working-copy",
            "POST",
            {**data, "content": "Older payload", "draft_version": "4"},
        )[0]
        == 200,
        "older working-copy request",
    )
    copy = props(admin, f"/admin/pages/{str(page_id)}/edit")["workingCopy"]
    check(
        copy["data"]["content"] == data["content"],
        "out-of-order autosave replaced a newer working copy",
    )
    check(
        "An updated working copy" not in public.request(f"/pages/{data['slug']}")[2],
        "working copy overwrote the published page",
    )
    save(admin, "pages", data)
    after = props(admin, f"/admin/pages/{str(page_id)}/edit")
    check(
        after["workingCopy"] is None and after["item"]["version"] == 3,
        "manual save did not clear the working copy",
    )
    old_revision = history[-1]["id"]
    check(
        admin.request(
            f"/admin/pages/{str(page_id)}/history/{str(old_revision)}/restore",
            "POST",
            {},
        )[0]
        == 303,
        "restore revision",
    )
    restored = props(admin, f"/admin/pages/{str(page_id)}/edit")
    check(
        "A useful page" in restored["workingCopy"]["data"]["content"],
        "revision restore did not create a working copy",
    )
    check(
        "An updated working copy" in public.request(f"/pages/{data['slug']}")[2],
        "revision restore changed live content before manual save",
    )
    admin.request(f"/admin/pages/{str(page_id)}/discard-working", "POST", {})
    data["version"] = str(after["item"]["version"])
    data["status"] = "scheduled"
    data["scheduled_epoch"] = str(int(time.time() * 1000) + 120000)
    save(admin, "pages", data)
    check(public.request(f"/pages/{data['slug']}")[0] == 404, "scheduled page was published early")
    fixtures.update(
        "items", {"scheduled_epoch": int(time.time() * 1000) - 1000}, [("id", "=", page_id)]
    )
    check(
        admin.request("/admin/content/publish-due", "POST", {})[0] == 200,
        "run scheduled site",
    )
    check(
        public.request(f"/pages/{data['slug']}")[0] == 200,
        "due content did not publish or its cache stayed stale",
    )
    check(admin.request(f"/admin/pages/{str(page_id)}/trash", "POST", {})[0] == 303, "trash page")
    check(public.request(f"/pages/{data['slug']}")[0] == 404, "trashed page stayed public")
    check(
        any(row["id"] == page_id for row in props(admin, "/admin/pages?status=trash")["items"]),
        "trash collection lost the page",
    )
    check(
        admin.request(f"/admin/pages/{str(page_id)}/restore", "POST", {})[0] == 303,
        "restore trashed page",
    )
    check(
        public.request(f"/pages/{data['slug']}")[0] == 200,
        "restoring a published page did not refresh its cache",
    )
    check(
        admin.request(f"/admin/pages/{str(page_id)}/permanent-delete", "POST", {})[0] == 422,
        "active page was permanently deleted without trashing",
    )
    admin.request(f"/admin/pages/{str(page_id)}/trash", "POST", {})
    admin.request(f"/admin/pages/{str(page_id)}/permanent-delete", "POST", {})
    check(
        fixtures.count("content_revisions", [("document_id", "=", page_id)]) == 0,
        "permanent deletion left revision bodies",
    )

    fixture = (ROOT / "public/images/coast.jpg").read_bytes()
    status, _, body = admin.upload_image(
        "/admin/media/upload",
        fixture,
        "image/jpeg",
        (1000, 750),
        extra_headers={"X-File-Name": "CMS%20coast.jpg"},
    )
    check(status == 201, "upload image into catalog")
    image = json.loads(body)
    check(image["id"] > 0, "upload did not register media metadata")
    gallery = props(admin, "/admin/media?q=CMS%20coast")
    check(any(row["id"] == image["id"] for row in gallery["images"]), "media search is stale")
    check(
        admin.request(
            f"/admin/media/{str(image['id'])}/save",
            "POST",
            {"title": "A quiet coast", "alt": "Calm water at the coast"},
        )[0]
        == 303,
        "save media metadata",
    )
    content = {
        "id": "",
        "title": "A protected media content item",
        "slug": f"cms-media-{suffix}",
        "excerpt": "A content item that protects a referenced image.",
        "content": f"## At the coast\n\n![Calm water][photo]\n\n[photo]: {image['url']}",
        "category": props(admin, "/admin/content/new")["item"]["category"],
        "status": "published",
        "image": image["url"],
        "image_alt": "A coast",
        "featured": "0",
        "published_at": "2026-11-03",
        "stay": "1",
        "tags": "",
    }
    location = save(admin, "content", content)
    content_id = int(re.search(r"/content/(\d+)/edit", location).group(1))
    check(
        admin.request(f"/admin/media/{str(image['id'])}/trash", "POST", {})[0] == 422,
        "referenced image was deleted",
    )
    content.update(
        id=str(content_id),
        content="## A text-only version\n\nThe original photograph remains in revision history.",
        image="",
    )
    save(admin, "content", content)
    check(
        admin.request(f"/admin/media/{str(image['id'])}/trash", "POST", {})[0] == 422,
        "revision image was deleted",
    )
    invalid = {
        **content,
        "content": "An external reference image.\n\n![Unsafe][remote]\n\n[remote]: https://example.com/a.jpg",
    }
    check(
        admin.request("/admin/content/save", "POST", invalid)[0] == 422,
        "external reference image bypassed upload-only validation",
    )
    code = {
        **content,
        "content": "## Image syntax in code\n\n```text\n![Example](https://example.com/a.jpg)\n```",
    }
    save(admin, "content", code)
    admin.request(f"/admin/content/{str(content_id)}/delete", "POST", {})
    verify_media_trash(admin, public, fixtures, image, fixture)
    print(
        "PASS CMS content: pages, GFM/SEO, private ordered working copies, revision restore, stale-save rejection, scheduling, trash/restore, referenced-media protection and the media trash",
        flush=True,
    )


def upload_trashed(admin, original):
    status, _, body = admin.upload_image("/admin/media/upload", original, "image/jpeg", (1000, 750))
    check(status == 201, "upload an image for the trash")
    image = json.loads(body)
    check(
        admin.request(f"/admin/media/{str(image['id'])}/trash", "POST", {})[0] == 303,
        "move an unused image to the trash",
    )
    return image


def verify_media_trash(admin, public, fixtures, image, original):
    media_id = str(image["id"])
    filename = image["url"].rsplit("/", 1)[1]
    storage = Path(os.environ["TEST_STORAGE_PATH"]) / "media"
    check(
        admin.request(f"/admin/media/{media_id}/permanent-delete", "POST", {})[0] == 422,
        "an image was deleted permanently without passing through the trash",
    )
    check(
        admin.request(f"/admin/media/{media_id}/trash", "POST", {})[0] == 303,
        "unused media could not be moved to the trash",
    )
    check(public.request(image["url"])[0] == 404, "a trashed image is still served")
    check(
        public.request(f"/media/.trash/{filename}")[0] in (403, 404),
        "the hidden trash folder is publicly reachable",
    )
    check(
        not (storage / filename).exists()
        and (storage / ".trash" / filename).read_bytes() == original,
        "the trashed file did not move to the hidden trash folder",
    )
    library = props(admin, "/admin/media")
    trash = props(admin, "/admin/media?status=trash")
    check(
        all(row["id"] != image["id"] for row in library["images"])
        and any(row["id"] == image["id"] for row in trash["images"])
        and trash["trashCount"] >= 1,
        "the media library or its trash lists the wrong images",
    )
    status, _, preview = admin.request(f"/admin/media/{media_id}/trashed", binary=True)
    check(status == 200 and preview == original, "the trash could not preview its image")
    check(
        public.request(f"/admin/media/{media_id}/trashed")[0] != 200,
        "a visitor could open a trashed image",
    )
    check(
        admin.request(f"/admin/media/{media_id}/restore", "POST", {})[0] == 303
        and public.request(image["url"], binary=True)[0] == 200,
        "a restored image is not served again",
    )
    admin.request(f"/admin/media/{media_id}/trash", "POST", {})
    check(
        admin.request(f"/admin/media/{media_id}/permanent-delete", "POST", {})[0] == 303,
        "a trashed image could not be deleted permanently",
    )
    check(
        fixtures.count("media_assets", [("id", "=", image["id"])]) == 0
        and not (storage / ".trash" / filename).exists(),
        "permanent deletion left the image or its file",
    )

    # The trash deletes images 30 days after they were moved there.
    expired = upload_trashed(admin, original)
    recent = upload_trashed(admin, original)
    day = 24 * 60 * 60 * 1000
    now = int(time.time() * 1000)
    fixtures.update("media_assets", {"trashed_epoch": now - 31 * day}, [("id", "=", expired["id"])])
    fixtures.update("media_assets", {"trashed_epoch": now - 29 * day}, [("id", "=", recent["id"])])
    fixtures.update("scheduled_jobs", {"next_epoch": now - 1000}, [("id", "=", "core:media-trash")])
    deadline = time.monotonic() + 20
    while fixtures.count("media_assets", [("id", "=", expired["id"])]) and (
        time.monotonic() < deadline
    ):
        time.sleep(0.25)
    expired_file = storage / ".trash" / expired["url"].rsplit("/", 1)[1]
    recent_file = storage / ".trash" / recent["url"].rsplit("/", 1)[1]
    check(
        fixtures.count("media_assets", [("id", "=", expired["id"])]) == 0
        and not expired_file.exists(),
        "the trash kept an image for more than 30 days",
    )
    check(
        fixtures.count("media_assets", [("id", "=", recent["id"])]) == 1 and recent_file.exists(),
        "the trash deleted an image before 30 days",
    )
    automatic = [
        ("entity", "=", "media"),
        ("entity_id", "=", expired["id"]),
        ("action", "=", "deleted"),
        ("actor", "=", "System"),
    ]
    check(fixtures.count("activity_logs", automatic) == 1, "the trash did not record its deletion")
    admin.request(f"/admin/media/{str(recent['id'])}/permanent-delete", "POST", {})


if __name__ == "__main__":
    run()
