"""Verify owner/editor/writer permissions, session revocation and managed navigation."""

import json
import os
import re
import secrets

from e2e import Client, check
from cms_content import props, save
from fixture_store import FixtureStore


def login(email, password):
    client = Client()
    client.request("/admin/login")
    status, _, body = client.request("/admin/login", "POST", {"email": email, "password": password})
    check(status == 303, "member login returned " + str(status) + ": " + body[:200])
    return client


def run():
    with FixtureStore.from_environment() as fixtures:
        verify(fixtures)


def verify(fixtures):
    owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    public = Client()
    suffix = secrets.token_hex(5)
    owner_id = props(owner, "/admin")["auth"]["admin"]["id"]
    check(
        owner.request("/admin/account", "POST", {"name": "   "})[0] == 422,
        "a blank display name passed normalization",
    )
    owner_details = fixtures.rows(
        "admins", ["id", "name", "email"], [("id", "=", owner_id)], limit=1
    )[0]
    check(
        owner.request(
            "/admin/team/save", "POST", {**owner_details, "role": "writer", "active": "1"}
        )[0]
        == 422,
        "the last owner could demote themself",
    )
    members = {}
    for role in ["writer", "editor"]:
        password = secrets.token_urlsafe(18)
        email = "cms-" + role + "-" + suffix + "@example.com"
        values = {
            "name": "CMS " + role,
            "email": email,
            "password": password,
            "role": role,
            "active": "1",
        }
        check(owner.request("/admin/team/save", "POST", values)[0] == 303, "create " + role)
        identifier = fixtures.rows("admins", ["id"], [("email", "=", email)], limit=1)[0]["id"]
        members[role] = {**values, "id": identifier, "client": login(email, password)}
    writer = members["writer"]["client"]
    editor = members["editor"]["client"]
    writer_props = props(writer, "/admin")
    check(
        "extensions" not in writer_props["auth"]["admin"]["capabilities"],
        "writer received owner capabilities",
    )
    check(
        writer_props["items"] == [] and writer_props["activity"] == [],
        "writer dashboard leaked other authors",
    )
    for path in [
        "/admin/team",
        "/admin/plugins",
        "/admin/themes",
        "/admin/settings",
        "/admin/subscribers",
        "/admin/tags",
        "/admin/categories",
        "/admin/navigation",
        "/admin/activity",
    ]:
        check(writer.request(path)[0] == 403, "writer accessed " + path)
    for path in [
        "/admin/team",
        "/admin/plugins",
        "/admin/themes",
        "/admin/settings",
        "/admin/subscribers",
    ]:
        check(editor.request(path)[0] == 403, "editor accessed " + path)
    for path in [
        "/admin/categories/save",
        "/admin/settings",
        "/admin/team/save",
        "/admin/content/publish-due",
    ]:
        check(writer.request(path, "POST", {})[0] == 403, "writer mutated " + path)
    category = props(writer, "/admin/content/new")["item"]["category"]
    document = {
        "id": "",
        "title": "A writer draft",
        "slug": "writer-" + suffix,
        "content": "A private first draft with enough content for site.",
        "excerpt": "A first draft.",
        "category": category,
        "image": "",
        "image_alt": "",
        "status": "draft",
        "featured": "0",
        "published_at": "2026-11-03",
        "stay": "1",
        "tags": "",
    }
    check(
        writer.request("/admin/content/save", "POST", {**document, "status": "published"})[0]
        == 422,
        "writer published content",
    )
    location = save(writer, "content", document)
    content_id = int(re.search(r"/content/(\d+)/edit", location).group(1))
    check(
        [item["id"] for item in props(writer, "/admin/content")["items"]] == [content_id],
        "writer list was not author scoped",
    )
    another = props(owner, "/admin/content")["items"]
    another_id = next(item["id"] for item in another if item["id"] != content_id)
    check(
        writer.request("/admin/content/" + str(another_id) + "/edit")[0] == 403,
        "writer opened another author editor",
    )
    check(
        writer.request(
            "/admin/content/working-copy",
            "POST",
            {**document, "id": another_id, "draft_version": "1"},
        )[0]
        == 403,
        "writer autosaved another author document",
    )
    document.update(id=str(content_id), status="published")
    save(editor, "content", document)
    check(
        public.request("/content/" + document["slug"])[0] == 200,
        "editor could not publish writer content",
    )
    check(
        writer.request("/admin/content/" + str(content_id) + "/trash", "POST", {})[0] == 403,
        "writer unpublished live content",
    )
    check(
        writer.request("/admin/content/" + str(content_id) + "/delete", "POST", {})[0] == 403,
        "writer deleted live content",
    )

    member_values = {key: value for key, value in members["writer"].items() if key != "client"}
    member_values.update(role="editor", password="")
    check(owner.request("/admin/team/save", "POST", member_values)[0] == 303, "change member role")
    check(
        writer.request("/admin/categories")[0] == 200,
        "new role was not applied to an existing session",
    )
    member_values["active"] = "0"
    owner.request("/admin/team/save", "POST", member_values)
    check(writer.request("/admin")[0] == 303, "deactivated account retained access")
    check(writer.request("/admin/login")[0] == 200, "deactivated account entered a redirect loop")
    check(
        writer.request(
            "/admin/login",
            "POST",
            {"email": member_values["email"], "password": members["writer"]["password"]},
        )[0]
        == 401,
        "deactivated account could log in",
    )
    member_values.update(active="1", password=secrets.token_urlsafe(18))
    owner.request("/admin/team/save", "POST", member_values)
    changed = login(member_values["email"], member_values["password"])
    session_copy = login(member_values["email"], member_values["password"])
    check(
        changed.request("/admin/account", "POST", {"name": "A changed display name"})[0] == 303,
        "save account profile",
    )
    new_password = secrets.token_urlsafe(18)
    check(
        changed.request(
            "/admin/password",
            "POST",
            {
                "current_password": member_values["password"],
                "new_password": new_password,
                "confirm_password": new_password,
                "return_to": "account",
            },
        )[0]
        == 303,
        "change own password",
    )
    check(
        changed.request("/admin")[0] == 200 and session_copy.request("/admin")[0] == 303,
        "password change did not retain only the current session",
    )

    page = {
        **document,
        "id": "",
        "title": "A navigation page",
        "slug": "navigation-" + suffix,
        "category": "",
        "status": "published",
    }
    page_content_id = int(re.search(r"/pages/(\d+)/edit", save(owner, "pages", page)).group(1))
    menu = {
        "label": "CMS menu " + suffix,
        "location": "header",
        "url": "",
        "content_id": str(page_content_id),
        "position": "0",
        "new_tab": "0",
    }
    check(
        editor.request("/admin/navigation/save", "POST", menu)[0] == 303,
        "editor page navigation save",
    )
    menu_id = fixtures.rows("menu_links", ["id"], [("label", "=", menu["label"])], limit=1)[0]["id"]
    nav = props(public, "/")["navigation"]["header"]
    check(
        any(link["url"] == "/pages/" + page["slug"] for link in nav),
        "navigation cache omitted new page link",
    )
    check(menu["label"] in public.request("/")[2], "navigation was not rendered in HTML")
    page.update(id=str(page_content_id), slug=page["slug"] + "-updated")
    save(owner, "pages", page)
    check(
        next(link for link in props(public, "/")["navigation"]["header"] if link["id"] == menu_id)[
            "url"
        ]
        == "/pages/" + page["slug"],
        "navigation did not follow a page slug change",
    )
    for unsafe in [
        "javascript:alert(1)",
        "//example.com",
        "/\\evil",
        "https://user:password@example.com",
    ]:
        check(
            editor.request(
                "/admin/navigation/save", "POST", {**menu, "content_id": "", "url": unsafe}
            )[0]
            == 422,
            "unsafe navigation address accepted",
        )
    owner.request("/admin/pages/" + str(page_content_id) + "/trash", "POST", {})
    check(
        all(link["id"] != menu_id for link in props(public, "/")["navigation"]["header"]),
        "trashed page remained in navigation",
    )
    owner.request("/admin/pages/" + str(page_content_id) + "/restore", "POST", {})
    check(
        any(link["id"] == menu_id for link in props(public, "/")["navigation"]["header"]),
        "restored page did not return to navigation",
    )
    owner.request("/admin/pages/" + str(page_content_id) + "/delete", "POST", {})
    check(
        fixtures.count("menu_links", [("id", "=", menu_id)]) == 0,
        "deleted page left a managed link",
    )
    entries = props(owner, "/admin/activity?entity=member")["entries"]
    check(
        entries and all(entry["entity"] == "member" for entry in entries),
        "activity filter or member auditing failed",
    )
    check(
        "password" not in json.dumps(props(owner, "/admin/team")["members"]),
        "team response exposed credential fields",
    )
    owner.request("/admin/content/" + str(content_id) + "/delete", "POST", {})
    for member in members.values():
        fixtures.delete("editor_drafts", [("user_id", "=", member["id"])])
        fixtures.delete("admins", [("id", "=", member["id"])])
    print(
        "PASS CMS management: role-scoped content, owner-only configuration, live permission changes, session revocation, safe page navigation and activity records",
        flush=True,
    )


if __name__ == "__main__":
    run()
