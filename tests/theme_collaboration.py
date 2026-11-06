"""Two real WebSocket peers share one authenticated theme channel."""

import json
import os

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


def permissions_and_events(owner, public, store, peer, other, token, version):
    route = f"/admin/themes/{peer.theme_id}"
    api = f"/api/theme-designer/{peer.theme_id}"
    bearer = {"Authorization": f"Bearer {token}"}
    peer.tool("get_design")
    changes = [
        event["params"]
        for event in peer.events
        if event.get("method") == "notifications/haxepress/design_changed"
    ]
    check(
        changes and changes[-1]["version"] == version,
        "LLM edits were not pushed live to the browser",
    )
    check(
        all(event["themeId"] == peer.theme_id for event in changes),
        "A change crossed its theme channel",
    )
    other.tool("get_design")
    check(
        not any(
            event.get("method") == "notifications/haxepress/design_changed"
            for event in other.events
        ),
        "Another theme received draft notifications",
    )
    original = store.rows(
        "theme_ai_connections", ["token_hash"], [("theme_id", "=", peer.theme_id)], limit=1
    )
    check(
        owner.request(
            f"{route}/ai/permissions", "POST", {"read": "1", "edit": "0", "media": "0"}, csrf=False
        )[0]
        == 419,
        "Permission changes bypassed CSRF",
    )
    check(
        post_json(owner, f"{route}/ai/permissions", {"read": "1", "edit": "invalid", "media": "1"})[
            0
        ]
        == 422,
        "Permission validation was bypassed",
    )
    check(
        post_json(owner, f"{route}/ai/permissions", {"read": "1", "edit": "0", "media": "0"})[0]
        == 200,
        "Read-only permissions could not be saved",
    )
    tools = peer.rpc("tools/list")["result"]["tools"]
    expected = [
        "get_design_guide",
        "get_design",
        "get_collection_schema",
        "search_theme_assets",
        "read_theme_asset_image",
    ]
    check([tool["name"] for tool in tools] == expected, "Browser tool permissions were not applied")
    check(
        public.request(f"{api}/design", "POST", {}, extra_headers=bearer)[0] == 403,
        "A read-only AI connection could write",
    )
    check(
        public.request(f"{api}/media", extra_headers=bearer)[0] == 403,
        "A denied media permission was ignored",
    )
    reply = peer.rpc(
        "tools/call",
        {
            "name": "edit_design",
            "arguments": {
                "expectedVersion": version,
                "operations": [{"action": "tokens", "values": {"accent": "#cc0000"}}],
            },
        },
    )
    check(
        "error" in reply or reply.get("result", {}).get("isError"),
        "A forbidden browser edit succeeded",
    )
    status, _, body = public.request(
        f"/mcp/themes/{peer.theme_id}",
        "POST",
        raw=json.dumps({"jsonrpc": "2.0", "id": 31, "method": "tools/list"}).encode(),
        content_type="application/json",
        extra_headers={
            **bearer,
            "Accept": "application/json, text/event-stream",
            "X-Haxepress-Permissions": '{"read":true,"edit":true,"media":true}',
        },
    )
    check(
        status == 200
        and [tool["name"] for tool in json.loads(body)["result"]["tools"]] == expected,
        "External permissions were forged through a header",
    )
    current = peer.tool("get_design")
    check(current["theme"]["version"] == version, "Permission failures changed the saved draft")
    check(
        store.rows(
            "theme_ai_connections", ["token_hash"], [("theme_id", "=", peer.theme_id)], limit=1
        )
        == original,
        "Saving permissions rotated a connection key",
    )
    check(
        post_json(owner, f"{route}/ai/permissions", {"read": "0", "edit": "1", "media": "1"})[0]
        == 200,
        "AI tools could not be disabled",
    )
    check(
        public.request(f"{api}/design", extra_headers=bearer)[0] == 403,
        "Disabled AI tools retained design access",
    )
    check(
        post_json(owner, f"{route}/ai/permissions", {"read": "1", "edit": "1", "media": "1"})[0]
        == 200,
        "AI permissions could not be restored",
    )
    restored = [tool["name"] for tool in peer.rpc("tools/list")["result"]["tools"]]
    check(
        len(restored) == 11 and "verify_theme_image" in restored,
        "The updated permission cache did not refresh",
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
        "PASS Shared theme WebSockets: admin-session authentication, trusted origins, no browser API key, live scoped changes, server-side read/edit/media permissions and key preservation",
        flush=True,
    )
