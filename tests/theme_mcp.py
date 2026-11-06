"""Verify real MCP clients, theme-scoped keys and the native draft API."""

import json
import os
from pathlib import Path
import secrets
import struct
import subprocess
import time
import zlib

from cms_content import props
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore
from validation import post_json
from websocket_lifecycle import WebSocket
from theme_collaboration import BrowserPeer, initial_browser, permissions_and_events

ROOT = Path(__file__).resolve().parents[1]


def large_png():
    width, height = 1024, 768

    def chunk(kind, data):
        payload = kind + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload))

    pixels = b"".join(b"\0" + secrets.token_bytes(width * 3) for _ in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(pixels, level=0))
        + chunk(b"IEND", b"")
    )


def run():
    owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    public = Client()
    previous = props(public, "/")["theme"]["id"]
    packages = []
    image = None
    peers = []
    email = "theme-ai-" + secrets.token_hex(5) + "@example.test"
    with FixtureStore.from_environment() as store:
        try:
            image_bytes = large_png()
            status, _, body = owner.upload_image(
                "/admin/media/upload", image_bytes, "image/png", (1024, 768)
            )
            check(status == 201, "The MCP large-image fixture could not be uploaded")
            image = json.loads(body)
            for name in ("AI design", "Other AI design"):
                status, headers, _ = post_json(
                    owner, "/admin/themes/create", {"name": name, "starter": "blank"}
                )
                check(status == 303, "MCP test design creation failed")
                packages.append(props(owner, headers["location"])["studio"]["id"])
            identifier, other = packages
            route = "/admin/themes/" + identifier
            peers.append(initial_browser(owner, store, identifier))
            peers.append(BrowserPeer(owner, other))
            api = "/api/theme-designer/" + identifier
            check(
                public.request(route + "/ai")[0] == 303,
                "Connection settings bypassed the admin guard",
            )
            check(
                owner.request(route + "/ai", "POST", {}, csrf=False)[0] == 419,
                "Connection creation bypassed CSRF",
            )
            check(
                owner.request(api + "/design")[0] == 401,
                "A browser cookie authorized the private bridge API",
            )
            status, headers, body = owner.request(route + "/ai", "POST", {})
            check(
                status == 200 and "no-store" in headers["cache-control"],
                "Connection creation failed",
            )
            connection = json.loads(body)
            token = connection["token"]
            check(
                connection["active"] and connection["expires"] > time.time() * 1000,
                "Connection expiry was not applied",
            )
            mcp = "/mcp/themes/" + identifier
            check(
                connection["hosted"]
                and connection["mcpPath"] == mcp
                and connection["websocketPath"] == mcp + "/ws",
                "The site-managed MCP service did not start",
            )
            keys = store.rows(
                "theme_ai_connections", ["token_hash"], [("theme_id", "=", identifier)], limit=1
            )
            check(
                len(keys) == 1
                and keys[0]["token_hash"] != token
                and len(keys[0]["token_hash"]) == 64,
                "A connection key was stored in plaintext",
            )
            check(
                json.loads(owner.request(route + "/ai")[2])["token"] is None,
                "An existing connection leaked its key",
            )
            bearer = {"Authorization": "Bearer " + token}
            check(owner.request(mcp)[0] == 401, "An admin cookie authorized MCP")
            for method in ("GET", "DELETE"):
                status, headers, _ = public.request(mcp, method, extra_headers=bearer)
                check(
                    status == 405 and "set-cookie" not in headers,
                    "MCP session methods were not stateless",
                )
            check(
                public.request(
                    mcp,
                    "POST",
                    raw=b"{",
                    extra_headers={
                        **bearer,
                        "Content-Type": "application/json",
                        "Accept": "application/json, text/event-stream",
                    },
                )[0]
                == 400,
                "The MCP adapter hid the SDK's parse error",
            )
            check(
                public.request(mcp, extra_headers={**bearer, "Origin": "https://untrusted.test"})[0]
                == 403,
                "An untrusted MCP origin was accepted",
            )
            check(
                public.request("/mcp/themes/" + other, extra_headers=bearer)[0] == 401,
                "The hosted MCP endpoint crossed its theme scope",
            )
            status, headers, _ = public.request(api + "/design", extra_headers=bearer)
            check(
                status == 200
                and "set-cookie" not in headers
                and "no-store" in headers["cache-control"],
                "Scoped bridge request created a session or could not read its design",
            )
            check(
                public.request("/api/theme-designer/" + other + "/design", extra_headers=bearer)[0]
                == 401,
                "A connection accessed another theme",
            )
            check(
                public.request(
                    api + "/design", extra_headers={**bearer, "Origin": "https://untrusted.test"}
                )[0]
                == 401,
                "A browser origin accessed the local bridge",
            )
            completed = subprocess.run(
                ["node", str(ROOT / "tests/theme_mcp_client.mjs")],
                cwd=ROOT,
                env={
                    **os.environ,
                    "TEST_THEME_ID": identifier,
                    "TEST_MCP_TOKEN": token,
                    "TEST_MCP_IMAGE_ID": str(image["id"]),
                    "TEST_MCP_IMAGE_BYTES": str(len(image_bytes)),
                },
                text=True,
                capture_output=True,
                timeout=120,
            )
            check(completed.returncode == 0, "Real MCP client failed: " + completed.stderr[-2500:])
            result = json.loads(completed.stdout)
            check(
                result["modern"]
                and result["legacy"]
                and result["imageRead"]
                and result["hosted"]
                and result["websocket"],
                "SDK protocol/image tests did not finish",
            )
            browser_owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
            browser_test = subprocess.run(
                ["node", str(ROOT / "tests/theme_browser_client.mjs")],
                cwd=ROOT,
                env={
                    **os.environ,
                    "TEST_THEME_ID": identifier,
                    "TEST_BROWSER_COOKIE": "; ".join(
                        key + "=" + value for key, value in browser_owner.cookies.items()
                    ),
                    "TEST_BROWSER_CSRF": browser_owner.csrf,
                },
                text=True,
                capture_output=True,
                timeout=90,
            )
            check(
                browser_test.returncode == 0, "Browser API failed: " + browser_test.stderr[-3000:]
            )
            browser_result = json.loads(browser_test.stdout)
            check(
                browser_result["browserApi"]
                and browser_result["webMcp"]
                and browser_result["permissions"]
                and browser_result["logout"],
                "Browser API checks did not finish",
            )
            result["version"] = browser_result["version"]
            print(
                "PASS Browser JavaScript/WebMCP: real server tools, draft edits, dirty protection, permission registration/revocation, logout and teardown",
                flush=True,
            )
            studio = props(owner, route + "/design")["studio"]
            check(
                studio["version"] == result["version"]
                and studio["publishedVersion"] == 0
                and not studio["enabled"],
                "MCP edits published or activated their theme",
            )
            check(props(public, "/")["theme"]["id"] == previous, "MCP changed the live website")
            check(
                json.loads(owner.request(route + "/design/status")[2])["version"]
                == result["version"],
                "The editor cannot observe an MCP draft version",
            )
            check(
                owner.request(route + "/ai/server")[0] == 404,
                "A client-side server download route remains",
            )
            check(
                "script" not in connection and "command" not in connection,
                "Client-side server setup remains in the connection API",
            )
            permissions_and_events(
                owner, public, store, peers[0], peers[1], token, result["version"]
            )
            for peer in peers:
                peer.close()
            peers.clear()
            admin = store.rows(
                "admins",
                ["id", "password"],
                [("email", "=", os.environ["TEST_ADMIN_EMAIL"])],
                limit=1,
            )[0]
            store.update("admins", {"active": 0}, [("id", "=", admin["id"])])
            try:
                check(
                    public.request(api + "/design", extra_headers=bearer)[0] == 401,
                    "A deactivated account retained AI access",
                )
            finally:
                store.update("admins", {"active": 1}, [("id", "=", admin["id"])])
            store.update(
                "admins", {"password": "invalidated-test-password"}, [("id", "=", admin["id"])]
            )
            try:
                check(
                    public.request(api + "/design", extra_headers=bearer)[0] == 401,
                    "A changed password retained AI access",
                )
            finally:
                store.update("admins", {"password": admin["password"]}, [("id", "=", admin["id"])])
            socket = WebSocket(
                os.environ["TEST_URL"], path=mcp + "/ws", headers=bearer, opened=False
            )
            try:
                socket.send(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}))
                opcode, source = socket.receive()
                check(
                    opcode == 1 and "result" in json.loads(source),
                    "The open MCP socket could not read tools",
                )
                status, _, body = owner.request(route + "/ai", "POST", {})
                replacement = json.loads(body)["token"]
                socket.send(json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}))
                check(socket.receive()[0] == 8, "A replaced token kept its open WebSocket access")
            finally:
                socket.socket.close()
            check(
                public.request(api + "/design", extra_headers=bearer)[0] == 401,
                "Replacing a connection left its old key valid",
            )
            bearer = {"Authorization": "Bearer " + replacement}
            check(
                public.request(api + "/design", extra_headers=bearer)[0] == 200,
                "Replacement connection failed",
            )
            store.update(
                "theme_ai_connections", {"expires_epoch": 1}, [("theme_id", "=", identifier)]
            )
            check(
                public.request(api + "/design", extra_headers=bearer)[0] == 401,
                "An expired connection remained authorized",
            )
            replacement = json.loads(owner.request(route + "/ai", "POST", {})[2])["token"]
            bearer = {"Authorization": "Bearer " + replacement}
            check(
                owner.request(
                    route + "/ai", "DELETE", raw=b"", extra_headers={"X-CSRF-TOKEN": owner.csrf}
                )[0]
                == 200,
                "Connection revocation failed",
            )
            check(
                public.request(api + "/design", extra_headers=bearer)[0] == 401,
                "A revoked connection still worked",
            )
            password = secrets.token_urlsafe(22)
            check(
                owner.request(
                    "/admin/team/save",
                    "POST",
                    {
                        "name": "AI editor",
                        "email": email,
                        "password": password,
                        "role": "editor",
                        "active": "1",
                    },
                )[0]
                == 303,
                "Permission test account creation failed",
            )
            member = login(email, password)
            check(
                member.request(route + "/ai", "POST", {})[0] == 403,
                "A non-manager created a design connection",
            )
            check(
                member.request(route + "/export")[0] == 403,
                "A non-manager exported a private theme",
            )
        finally:
            for peer in peers:
                peer.close()
            for identifier in packages:
                owner.request("/admin/themes/" + identifier + "/uninstall", "POST", {})
            if image is not None:
                owner.request("/admin/media/" + str(image["id"]) + "/delete", "POST", {})
            store.delete("admins", [("email", "=", email)])
    print(
        "PASS Theme MCP: official legacy/modern clients over HTTP/WebSocket, draft edits and images, scoped keys, open-socket revocation, origins, permissions and stateless API",
        flush=True,
    )


if __name__ == "__main__":
    run()
