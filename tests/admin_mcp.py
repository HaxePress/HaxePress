"""Verify per-link MCP authentication, header authorization and native media/content tools."""

import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import struct
import time
from urllib.parse import urlsplit

from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore
from validation import post_json
from websocket_lifecycle import WebSocket

STATE = "/admin/ai"
ACCEPT = "application/json, text/event-stream"


def issue(owner, profile="claude", hours=None):
    payload = {"profile": profile} if hours is None else {"profile": profile, "hours": hours}
    status, headers, body = post_json(owner, f"{STATE}/sessions", payload)
    check(status == 201 and "no-store" in headers["cache-control"], "MCP issuance failed")
    return json.loads(body)


def endpoint(connection):
    return urlsplit(connection["url"]).path


def credentials(connection):
    return {"Authorization": f"Bearer {connection['token']}", "Accept": ACCEPT}


def rpc(public, connection, method, params=None):
    request = {"jsonrpc": "2.0", "id": 1, "method": method}
    if params is not None:
        request["params"] = params
    status, _, body = post_json(public, endpoint(connection), request, credentials(connection))
    check(status == 200, f"MCP {method} returned {status}: {body[:250]}")
    response = json.loads(body)
    check("result" in response, f"MCP {method} failed: {response.get('error')}")
    return response["result"]


def tool_names(public, connection):
    return {item["name"] for item in rpc(public, connection, "tools/list")["tools"]}


def session_status(owner, connection):
    status, _, body = owner.request(STATE)
    check(status == 200, "MCP session state was unavailable")
    return next(
        (item for item in json.loads(body)["sessions"] if item["id"] == connection["id"]),
        None,
    )


def call(public, connection, name, arguments):
    return rpc(public, connection, "tools/call", {"name": name, "arguments": arguments})


def succeeded(result):
    check(
        not result.get("isError"),
        f"Tool failed: {result.get('content', [{}])[0].get('text', '')[:250]}",
    )
    return result["structuredContent"]


def refused(result):
    return (
        bool(result.get("isError")) or result.get("structuredContent", {}).get("status", 0) >= 400
    )


def routes_of(public, connection):
    data = succeeded(call(public, connection, "get_admin_routes", {}))["data"]
    return {route["path"] for route in data["routes"]}


def verify_role_limits(owner, public):
    """An MCP link acts with its account's current role and nothing more."""
    password = secrets.token_urlsafe(18)
    email = f"mcp-role-{secrets.token_hex(4)}@example.test"
    member = {"name": "MCP Editor", "email": email, "role": "editor", "password": password}
    check(
        owner.request("/admin/team/save", "POST", {**member, "active": "1"})[0] == 303,
        "Could not create an editor account",
    )
    with FixtureStore.from_environment() as store:
        member_id = store.rows("admins", ["id"], [("email", "=", email)], limit=1)[0]["id"]
    category = f"MCP role {secrets.token_hex(3)}"
    connection = issue(login(email, password), "claude")
    try:
        # The Authorization scheme is case-insensitive; the token after it is not.
        lowercase = {**credentials(connection), "Authorization": f"bearer {connection['token']}"}
        request = {"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
        status, _, body = post_json(public, endpoint(connection), request, lowercase)
        check(
            status == 200 and "result" in json.loads(body),
            f"A lowercase bearer scheme failed: {status}",
        )
        names = tool_names(public, connection)
        check(
            {"list_categories", "save_category", "list_content"} <= names
            and not {"save_site_settings", "list_themes", "create_theme_draft"} & names,
            f"An editor's MCP tools do not match the role: {sorted(names)}",
        )
        routes = routes_of(public, connection)
        forbidden = (
            "/admin/settings",
            "/admin/team",
            "/admin/roles",
            "/admin/themes",
            "/admin/plugins",
            "/admin/backups",
        )
        check(
            "/admin/categories/save" in routes
            and not any(path.startswith(forbidden) for path in routes),
            "MCP route discovery listed areas outside the editor role",
        )
        succeeded(call(public, connection, "save_category", {"name": category}))
        settings = call(
            public,
            connection,
            "write_admin",
            {"path": "/admin/settings", "method": "POST", "data": {"site_name": "Taken over"}},
        )
        check(refused(settings), "An editor changed site settings through MCP")

        # A lower role applies to the same link on its next request.
        demoted = {**member, "id": str(member_id), "role": "writer", "password": ""}
        check(
            owner.request("/admin/team/save", "POST", {**demoted, "active": "1"})[0] == 303,
            "Could not change the account's role",
        )
        attempt = call(
            public,
            connection,
            "write_admin",
            {
                "path": "/admin/categories/save",
                "method": "POST",
                "data": {"name": f"{category} after"},
            },
        )
        check(refused(attempt), "A demoted account kept its category rights over MCP")
        routes = routes_of(public, connection)
        check(
            "/admin/categories/save" not in routes and "/admin/content/save" in routes,
            "MCP route discovery did not follow the new role",
        )
        with FixtureStore.from_environment() as store:
            check(
                store.count("categories", [("name", "=", f"{category} after")]) == 0,
                "A refused MCP request created a category",
            )

        # A deactivated account's link stops working.
        check(
            owner.request("/admin/team/save", "POST", {**demoted, "active": "0"})[0] == 303,
            "Could not deactivate the account",
        )
        request = {"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
        status = post_json(public, endpoint(connection), request, credentials(connection))[0]
        check(status == 401, f"A deactivated account's MCP link returned {status}")
    finally:
        with FixtureStore.from_environment() as store:
            store.delete("categories", [("name", "=", category)])
            store.delete("admins", [("id", "=", member_id)])
    print(
        "PASS Admin MCP: links act with their account's current role; demotion and deactivation apply at once",
        flush=True,
    )


def verify_role_edits(owner, public):
    """Editing a role's capabilities or the account's password applies to existing MCP links."""
    role = f"mcp_role_{secrets.token_hex(4)}"
    role_form = {"key": role, "name": "MCP taxonomy role", "description": "MCP role edit test"}
    password = secrets.token_urlsafe(18)
    email = f"mcp-edit-{secrets.token_hex(4)}@example.test"
    member = {"name": "MCP Role Edit", "email": email, "role": role}
    category = f"MCP edit {secrets.token_hex(3)}"
    attempted = f"{category} after"
    member_id = None
    status = owner.request(
        "/admin/roles/create",
        "POST",
        {
            **role_form,
            "enabled": "1",
            "capabilities": json.dumps(["content", "taxonomy", "account"]),
        },
    )[0]
    check(status == 303, f"Could not create a custom role: {status}")
    try:
        status = owner.request(
            "/admin/team/save",
            "POST",
            {**member, "id": "", "active": "1", "password": password},
        )[0]
        check(status == 303, f"Could not create an account with the custom role: {status}")
        with FixtureStore.from_environment() as store:
            member_id = store.rows("admins", ["id"], [("email", "=", email)], limit=1)[0]["id"]
        connection = issue(login(email, password), "claude")
        check(
            "save_category" in tool_names(public, connection),
            "The custom role's MCP tools lack category management",
        )
        succeeded(call(public, connection, "save_category", {"name": category}))

        # Removing a capability from the role applies to the same link on its next request.
        status = owner.request(
            f"/admin/roles/{role}/save",
            "POST",
            {**role_form, "enabled": "1", "capabilities": json.dumps(["content", "account"])},
        )[0]
        check(status == 303, f"Could not edit the role's capabilities: {status}")
        attempt = call(
            public,
            connection,
            "write_admin",
            {"path": "/admin/categories/save", "method": "POST", "data": {"name": attempted}},
        )
        check(refused(attempt), "A link kept a capability its role no longer grants")
        routes = routes_of(public, connection)
        check(
            "/admin/categories/save" not in routes and "/admin/content/save" in routes,
            "MCP route discovery did not follow the edited role",
        )
        with FixtureStore.from_environment() as store:
            check(
                store.count("categories", [("name", "=", attempted)]) == 0,
                "A refused MCP request created a category",
            )

        # A new password stops links issued with the old one.
        changed = {
            **member,
            "id": str(member_id),
            "active": "1",
            "password": secrets.token_urlsafe(18),
        }
        status = owner.request("/admin/team/save", "POST", changed)[0]
        check(status == 303, f"Could not change the account's password: {status}")
        request = {"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
        status = post_json(public, endpoint(connection), request, credentials(connection))[0]
        check(status == 401, f"A link survived a password change: {status}")
    finally:
        with FixtureStore.from_environment() as store:
            store.delete("categories", [("name", "in", [category, attempted])])
            if member_id is not None:
                store.delete("admins", [("id", "=", member_id)])
        if owner.request(f"/admin/roles/{role}/delete", "POST", {})[0] != 303:
            with FixtureStore.from_environment() as store:
                store.delete("role_grants", [("role_key", "=", role)])
                store.delete("roles", [("key", "=", role)])
        with FixtureStore.from_environment() as store:
            check(store.count("roles", [("key", "=", role)]) == 0, "The test role was not removed")
    print(
        "PASS Admin MCP: editing a role's capabilities and changing the password apply to existing links",
        flush=True,
    )


def verify_expiry(owner, public):
    """A link's expiry is chosen when it is generated and can change until a client connects."""
    hour = issue(owner, "cursor", hours=1)
    remaining = hour["expires"] / 1000 - time.time()
    check(3000 < remaining <= 3600, f"A one-hour MCP link expires in {remaining:.0f} seconds")
    status, _, _ = post_json(owner, f"{STATE}/sessions", {"profile": "cursor", "hours": 5})
    check(status == 422, "An unsupported MCP link lifetime was accepted")
    status, _, body = post_json(owner, f"{STATE}/sessions/{hour['id']}/expiry", {"hours": 720})
    changed = next(item for item in json.loads(body)["sessions"] if item["id"] == hour["id"])
    check(
        status == 200 and changed["expires"] - hour["expires"] > 700 * 3600 * 1000,
        "An unused MCP link's expiry did not change",
    )
    tool_names(public, hour)
    # Links live in the database, so they keep their lifetime across restarts.
    with FixtureStore.from_environment() as store:
        stored = store.rows(
            "admin_mcp_links",
            ["expires_epoch", "token_hash", "first_seen_epoch"],
            [("id", "=", hour["id"])],
            limit=1,
        )
    check(
        len(stored) == 1
        and stored[0]["expires_epoch"] == changed["expires"]
        and stored[0]["token_hash"] == hashlib.sha256(hour["token"].encode()).hexdigest()
        and stored[0]["first_seen_epoch"] > 0,
        f"The MCP link was not kept in the database: {stored}",
    )
    status, _, body = post_json(owner, f"{STATE}/sessions/{hour['id']}/expiry", {"hours": 1})
    check(
        status == 409 and session_status(owner, hour)["expires"] == changed["expires"],
        f"A connected MCP link's expiry changed: {status} {body[:160]}",
    )
    owner.request(f"{STATE}/sessions/{hour['id']}", "DELETE", {})
    print(
        "PASS Admin MCP: chosen link lifetimes kept in the database, expiry changes before first use, unknown links 404",
        flush=True,
    )


def verify_browser(owner):
    origin = os.environ["TEST_URL"]
    cookies = "; ".join(f"{key}={value}" for key, value in owner.cookies.items())
    browser = WebSocket(
        origin, path="/admin/ai/ws", headers={"Cookie": cookies, "Origin": origin}, opened=False
    )
    try:
        browser.send(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}))
        opcode, source = browser.receive()
        result = json.loads(source)["result"]
        check(
            opcode == 1 and any(tool["name"] == "set_content_cover" for tool in result["tools"]),
            "Signed-in JavaScript MCP did not expose native media tools",
        )
    finally:
        browser.socket.close()


def verify_media_and_content(owner, public, connection):
    image = (Path(__file__).parent / "fixtures/media/logo-transparent.png").read_bytes()
    width, height = struct.unpack_from(">II", image, 16)
    digest = hashlib.sha256(image).hexdigest()
    staged = call(
        public,
        connection,
        "upload_media_image",
        {"name": "MCP cover.png", "base64": base64.b64encode(image).decode()},
    )
    metadata = succeeded(staged)
    check(metadata["sha256"] == digest and metadata["status"] == 202, "Staged image hash changed")
    echoed = next(item for item in staged["content"] if item["type"] == "image")
    check(base64.b64decode(echoed["data"]) == image, "Image preview did not echo the original file")
    confirmation = {"id": metadata["uploadId"], "sha256": digest, "width": width, "height": height}
    rejected = call(public, connection, "verify_media_image", {**confirmation, "sha256": "0" * 64})
    check(rejected.get("isError"), "MCP accepted a mismatched upload hash")
    saved = succeeded(call(public, connection, "verify_media_image", confirmation))["data"]
    check(
        saved["id"] and saved["url"].startswith("/media/"),
        "The verified image did not enter managed media",
    )

    category = f"MCP category {secrets.token_hex(4)}"
    succeeded(call(public, connection, "save_category", {"name": category}))
    slug = f"mcp-image-{secrets.token_hex(5)}"
    succeeded(
        call(
            public,
            connection,
            "create_content",
            {
                "collection": "entry",
                "fields": {
                    "title": "MCP image test",
                    "slug": slug,
                    "body": "Original body.",
                    "excerpt": "A managed image workflow test.",
                    "category": category,
                },
            },
        )
    )
    with FixtureStore.from_environment() as store:
        row = store.rows("items", ["id", "version"], [("slug", "=", slug)], limit=1)[0]
        category_id = store.rows("categories", ["id"], [("name", "=", category)], limit=1)[0]["id"]
    document = {"collection": "entry", "id": row["id"]}
    try:
        cover = {
            **document,
            "expectedVersion": row["version"],
            "mediaId": saved["id"],
            "alt": "Cover text",
        }
        succeeded(call(public, connection, "set_content_cover", cover))
        stale = call(public, connection, "insert_content_image", cover)
        check(stale.get("isError"), "A stale image edit overwrote the current item")
        item = succeeded(call(public, connection, "get_content", document))["data"]["props"]["item"]
        check(
            item["image"] == saved["url"] and item["image_alt"] == "Cover text",
            "The cover image was not saved",
        )
        inline = {**cover, "expectedVersion": item["version"], "alt": "Inline text"}
        succeeded(call(public, connection, "insert_content_image", inline))
        item = succeeded(call(public, connection, "get_content", document))["data"]["props"]["item"]
        check(
            f"![Inline text]({saved['url']})" in item["content"]
            and "Original body." in item["content"],
            "The inline image or original article body was lost",
        )
        # MCP clients move items to the trash; only people delete them permanently.
        succeeded(call(public, connection, "trash_content", document))
        for path in (
            f"/admin/content/{row['id']}/permanent-delete",
            f"/admin/content/{row['id']}/delete",
            f"/admin/media/{saved['id']}/permanent-delete",
        ):
            attempt = call(public, connection, "write_admin", {"path": path, "method": "POST"})
            check(refused(attempt), f"An MCP client reached {path}")
        routes = succeeded(call(public, connection, "get_admin_routes", {}))["data"]["routes"]
        listed = {route["path"] for route in routes}
        permanent = {
            "/admin/content/{id}/delete",
            "/admin/content/{id}/permanent-delete",
            "/admin/pages/{id}/permanent-delete",
            "/admin/collections/{kind}/{id}/permanent-delete",
            "/admin/media/{id}/permanent-delete",
        }
        check(
            "/admin/content/{id}/trash" in listed and not listed & permanent,
            "MCP route discovery listed permanent deletes",
        )
        entry = [("entity", "=", "entry"), ("entity_id", "=", row["id"])]
        with FixtureStore.from_environment() as store:
            check(
                store.count("items", [("id", "=", row["id"]), ("status", "=", "trash")]) == 1,
                "An MCP client deleted trashed content",
            )
            check(
                store.count("activity_logs", [*entry, ("source", "=", "mcp")]) >= 3,
                "MCP changes were not recorded as MCP activity",
            )
        activity = owner.request("/admin/activity")[2]
        check(
            'class="featured-text"' in activity
            and " MCP</span>" in activity
            and "Via MCP" not in activity,
            "The activity page did not mark MCP changes",
        )
    finally:
        owner.request(f"/admin/content/{row['id']}/trash", "POST", {})
        owner.request(f"/admin/content/{row['id']}/permanent-delete", "POST", {})
        owner.request(f"/admin/media/{saved['id']}/trash", "POST", {})
        owner.request(f"/admin/media/{saved['id']}/permanent-delete", "POST", {})
        owner.request(f"/admin/categories/{category_id}/delete", "POST", {})
    with FixtureStore.from_environment() as store:
        check(
            store.count("activity_logs", [*entry, ("action", "=", "deleted"), ("source", "=", "")])
            == 1,
            "A person's permanent delete was not recorded as their own activity",
        )


def verify_end_of_input(owner, public, connection):
    """`$` also matches before a final line break on the server; JSON Schema `$` does not."""
    for ending in ["\n", "\r\n", "\u2028"]:
        status, _, _ = post_json(owner, f"{STATE}/sessions", {"profile": f"claude{ending}"})
        check(status == 422, f"An MCP profile ending in {ending!r} was accepted")
        result = call(public, connection, "list_content", {"collection": f"entry{ending}"})
        message = result.get("content", [{}])[0].get("text", "")
        check(
            result.get("isError") and "must match pattern" in message,
            f"An MCP argument ending in {ending!r} matched its schema pattern: {message[:200]}",
        )


def run():
    owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    public = Client()
    check(
        "Connect AI" in owner.request("/admin/settings")[2],
        "Connect AI was missing from admin pages",
    )
    verify_browser(owner)
    first = issue(owner)
    second = issue(owner, "codex")
    check(
        first["url"] != second["url"] and first["token"] != second["token"],
        "MCP links shared credentials",
    )
    check(public.request(endpoint(first))[0] == 401, "A session URL granted unauthenticated access")
    unknown = f"/mcp/sessions/{secrets.token_urlsafe(24)[:32]}"
    check(
        public.request(unknown)[0] == 404
        and public.request(unknown, extra_headers=credentials(first))[0] == 404,
        "An MCP URL that was never generated did not return 404",
    )
    verify_expiry(owner, public)
    verify_role_limits(owner, public)
    verify_role_edits(owner, public)
    check(
        public.request(endpoint(first), extra_headers=credentials(second))[0] == 401,
        "A bearer crossed its session audience",
    )
    check(
        public.request(
            endpoint(first),
            extra_headers={**credentials(first), "Origin": "https://untrusted.test"},
        )[0]
        == 403,
        "Untrusted origin was accepted",
    )
    status, _, _ = public.request(
        endpoint(first),
        "POST",
        raw=b"{",
        content_type="application/json",
        extra_headers=credentials(first),
    )
    check(status == 400, "An invalid MCP message was accepted")
    unused = session_status(owner, first)
    check(
        unused["firstSeenAt"] is None and unused["lastSeenAt"] is None,
        "A rejected request recorded MCP activity",
    )
    catalog = rpc(public, first, "tools/list")["tools"]
    first_use = session_status(owner, first)
    check(
        isinstance(first_use["firstSeenAt"], (float, int))
        and first_use["firstSeenAt"] == first_use["lastSeenAt"],
        "The first successful MCP request did not initialize both timestamps",
    )
    names = {tool["name"] for tool in catalog}
    for name in ("upload_media_image", "upload_theme_image"):
        upload = next(tool for tool in catalog if tool["name"] == name)
        check(
            upload["_meta"]["openai/fileParams"] == ["file"],
            "Image attachment input was not described",
        )
    denied = call(
        public,
        first,
        "upload_media_image",
        {"file": {"file_id": "invalid", "download_url": f"{os.environ['TEST_URL']}/"}},
    )
    check(denied.get("isError"), "The image tool accepted a non-attachment origin")
    verify_end_of_input(owner, public, first)
    expected = {
        "list_content",
        "get_content",
        "upload_media_image",
        "verify_media_image",
        "set_content_cover",
        "insert_content_image",
        "list_themes",
        "edit_theme_design",
        "upload_theme_image",
        "set_theme_block_image",
        "list_plugins",
        "list_navigation",
        "list_backup_schedules",
    }
    check(expected <= names and len(names) >= 35, "MCP discovery omitted native admin tools")
    check(
        {"trash_content", "restore_content", "trash_media_image", "restore_media_image"} <= names
        and not {"permanently_delete_content", "delete_media_image"} & names,
        "MCP tools still offer permanent deletes",
    )
    verify_media_and_content(owner, public, first)
    latest = session_status(owner, first)
    check(
        latest["firstSeenAt"] == first_use["firstSeenAt"]
        and latest["lastSeenAt"] > first_use["lastSeenAt"]
        and session_status(owner, second)["lastSeenAt"] is None,
        "Activity timestamps changed the first seen value or crossed session boundaries",
    )
    for profile in ("gemini", "cursor", "copilot", "grok"):
        connection = issue(owner, profile)
        check(
            connection["profile"] == profile and "get_content" in tool_names(public, connection),
            f"The {profile} profile could not connect using its bearer",
        )
        check(
            owner.request(f"{STATE}/sessions/{connection['id']}", "DELETE", {})[0] == 200,
            f"The {profile} session could not be revoked",
        )
    chatgpt = issue(owner, "chatgpt")
    check(
        chatgpt["token"] and "get_content" in tool_names(public, chatgpt),
        "ChatGPT desktop's bearer connection failed",
    )
    check(public.request(endpoint(chatgpt))[0] == 401, "The ChatGPT URL granted anonymous access")
    state = json.loads(owner.request(STATE)[2])
    check(
        all("token" not in item for item in state["sessions"]), "Panel state exposed access tokens"
    )
    check(
        owner.request(f"{STATE}/sessions/{first['id']}", "DELETE", {})[0] == 200,
        "Session could not be revoked",
    )
    check(
        public.request(endpoint(first), extra_headers=credentials(first))[0] == 404,
        "A revoked MCP URL did not return 404",
    )
    check(session_status(owner, first) is None, "Revoked session stayed in the panel")
    check("list_content" in tool_names(public, second), "Revocation affected another connection")
    owner.request(f"{STATE}/sessions/{second['id']}", "DELETE", {})
    owner.request(f"{STATE}/sessions/{chatgpt['id']}", "DELETE", {})
    print(
        "PASS Admin MCP: client profiles, per-link first/last seen, revocation and verified article images",
        flush=True,
    )


if __name__ == "__main__":
    run()
