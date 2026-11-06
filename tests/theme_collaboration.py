"""Two real WebSocket peers share one authenticated theme channel."""

import json
import os

from admin_mcp import call, session_status
from e2e import check
from validation import post_json
from websocket_lifecycle import WebSocket


class BrowserPeer:
    def __init__(self, owner, theme_id):
        self.theme_id = theme_id
        self.events = []
        self.sequence = 0
        self.socket = WebSocket(
            os.environ["TEST_URL"],
            path=f"/admin/themes/{theme_id}/ai/ws",
            headers={
                "Cookie": "; ".join(f"{key}={value}" for key, value in owner.cookies.items()),
                "Origin": os.environ["TEST_URL"],
            },
            opened=False,
        )

    def rpc(self, method, params=None):
        self.sequence += 1
        message = {"jsonrpc": "2.0", "id": self.sequence, "method": method}
        if params is not None:
            message["params"] = params
        self.socket.send(json.dumps(message))
        while True:
            opcode, source = self.socket.receive()
            if opcode == 8:
                raise PermissionError("The authenticated browser socket was closed")
            check(opcode == 1, "Unexpected binary collaboration message")
            reply = json.loads(source)
            if reply.get("id") == self.sequence:
                return reply
            self.events.append(reply)

    def tool(self, name, arguments=None):
        reply = self.rpc("tools/call", {"name": name, "arguments": arguments or {}})
        check("result" in reply, f"The browser tool was rejected: {str(reply.get('error'))}")
        result = reply["result"]
        check(not result.get("isError"), "The browser tool failed")
        return result.get("structuredContent") or json.loads(result["content"][0]["text"])

    def close(self):
        self.socket.socket.close()


def reject_socket(path, headers):
    try:
        socket = WebSocket(os.environ["TEST_URL"], path=path, headers=headers, opened=False)
    except AssertionError:
        return
    socket.socket.close()
    raise AssertionError("An unauthenticated or untrusted WebSocket connected")


def initial_browser(owner, store, theme_id):
    path = f"/admin/themes/{theme_id}/ai/ws"
    reject_socket(path, {"Origin": os.environ["TEST_URL"]})
    cookies = "; ".join(f"{key}={value}" for key, value in owner.cookies.items())
    reject_socket(path, {"Origin": "https://untrusted.test", "Cookie": cookies})
    reject_socket(path, {"Cookie": cookies})
    peer = BrowserPeer(owner, theme_id)
    snapshot = peer.tool("get_design")
    check(snapshot["theme"]["id"] == theme_id, "A browser socket read a different theme")
    check(
        store.count("theme_ai_connections", [("theme_id", "=", theme_id)]) == 0,
        "The browser needed or created an external connection key",
    )
    return peer


def permissions_and_events(owner, public, peer, other, connection, version):
    route = f"/admin/themes/{peer.theme_id}"
    peer.tool("get_design")
    changes = [
        event["params"]
        for event in peer.events
        if event.get("method") == "notifications/haxepress/design_changed"
    ]
    check(changes and changes[-1]["version"] == version, "Remote edits were not pushed live")
    check(
        all(event["themeId"] == peer.theme_id for event in changes), "A change crossed its channel"
    )
    other.tool("get_design")
    check(
        not any(
            event.get("method") == "notifications/haxepress/design_changed"
            for event in other.events
        ),
        "Another theme received draft notifications",
    )

    original = session_status(owner, connection)
    policy = {"read": "1", "edit": "0", "media": "0"}
    check(
        owner.request(f"{route}/ai/permissions", "POST", policy, csrf=False)[0] == 419,
        "Theme permissions bypassed CSRF",
    )
    check(
        post_json(owner, f"{route}/ai/permissions", {**policy, "edit": "invalid"})[0] == 422,
        "Theme permission validation was bypassed",
    )
    check(
        post_json(owner, f"{route}/ai/permissions", policy)[0] == 200,
        "Could not make theme read-only",
    )
    expected = [
        "get_design_guide",
        "get_design",
        "preview_theme",
        "get_collection_schema",
        "search_theme_assets",
        "read_theme_asset_image",
    ]
    tools = peer.rpc("tools/list")["result"]["tools"]
    check([tool["name"] for tool in tools] == expected, "Browser permission filtering changed")
    edits = {
        "expectedVersion": version,
        "operations": [{"action": "tokens", "values": {"accent": "#cc0000"}}],
    }
    remote = {"themeId": peer.theme_id}
    check(
        call(public, connection, "edit_theme_design", {**remote, **edits}).get("isError"),
        "A read-only theme accepted a remote edit",
    )
    check(
        call(public, connection, "search_media_for_theme", remote).get("isError"),
        "A denied theme could browse shared media",
    )
    reply = peer.rpc("tools/call", {"name": "edit_design", "arguments": edits})
    check(
        "error" in reply or reply.get("result", {}).get("isError"),
        "A read-only browser edited a theme",
    )
    check(peer.tool("get_design")["theme"]["version"] == version, "Denied edits changed the theme")
    current = session_status(owner, connection)
    stable_fields = ("id", "profile", "url", "expires", "firstSeenAt")
    check(
        current is not None
        and all(current[field] == original[field] for field in stable_fields)
        and current["lastSeenAt"] >= original["lastSeenAt"],
        "Changing theme permissions changed the global MCP session identity",
    )

    check(
        post_json(owner, f"{route}/ai/permissions", {**policy, "read": "0"})[0] == 200,
        "Theme AI tools could not be disabled",
    )
    check(
        call(public, connection, "get_theme_design", remote).get("isError"),
        "A disabled theme still returned its draft",
    )
    check(
        not call(public, connection, "get_theme_design", {"themeId": other.theme_id}).get(
            "isError"
        ),
        "A theme policy affected another theme",
    )
    check(
        post_json(owner, f"{route}/ai/permissions", {"read": "1", "edit": "1", "media": "1"})[0]
        == 200,
        "Theme AI permissions could not be restored",
    )
    restored = peer.rpc("tools/list")["result"]["tools"]
    check(
        len(restored) == 12 and any(tool["name"] == "verify_theme_image" for tool in restored),
        "The scoped browser catalog did not refresh",
    )
    notifications = [
        event
        for event in peer.events
        if event.get("method") == "notifications/haxepress/permissions"
    ]
    check(
        any(event["params"]["permissions"]["edit"] is False for event in notifications),
        "Browser permission changes were not pushed",
    )
    print(
        "PASS Theme collaboration: isolated live changes, browser access and scoped permissions",
        flush=True,
    )
