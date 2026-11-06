"""Verify standard MCP clients, scoped theme tools and browser collaboration."""

import json
import os
from pathlib import Path
import secrets
import struct
import subprocess
import zlib

from admin_mcp import credentials, endpoint, issue, tool_names
from cms_content import props
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore
from validation import post_json
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
    email = f"theme-ai-{secrets.token_hex(5)}@example.test"
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
            route = f"/admin/themes/{identifier}"
            peers.append(initial_browser(owner, store, identifier))
            peers.append(BrowserPeer(owner, other))
            api = f"/api/theme-designer/{identifier}"
            check(
                public.request(f"{route}/ai")[0] == 303, "Theme settings bypassed the admin guard"
            )
            connection = issue(owner)
            headers = credentials(connection)
            check(
                public.request(api + "/design", extra_headers=headers)[0] == 401,
                "The public bearer directly authorized a private theme route",
            )
            check(
                owner.request(endpoint(connection))[0] == 401,
                "An admin cookie authorized the remote URL",
            )
            completed = subprocess.run(
                ["node", str(ROOT / "tests/theme_mcp_client.mjs")],
                cwd=ROOT,
                env={
                    **os.environ,
                    "TEST_THEME_ID": identifier,
                    "TEST_MCP_TOKEN": connection["token"],
                    "TEST_MCP_URL": connection["url"],
                    "TEST_MCP_IMAGE_ID": str(image["id"]),
                    "TEST_MCP_IMAGE_BYTES": str(len(image_bytes)),
                },
                text=True,
                capture_output=True,
                timeout=120,
            )
            check(completed.returncode == 0, f"Real MCP client failed: {completed.stderr[-2500:]}")
            result = json.loads(completed.stdout)
            check(
                result["modern"] and result["legacy"] and result["imageRead"],
                "SDK protocol or theme image tests did not finish",
            )
            browser_owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
            browser_test = subprocess.run(
                ["node", str(ROOT / "tests/theme_browser_client.mjs")],
                cwd=ROOT,
                env={
                    **os.environ,
                    "TEST_THEME_ID": identifier,
                    "TEST_BROWSER_COOKIE": "; ".join(
                        f"{key}={value}" for key, value in browser_owner.cookies.items()
                    ),
                    "TEST_BROWSER_CSRF": browser_owner.csrf,
                },
                text=True,
                capture_output=True,
                timeout=90,
            )
            check(
                browser_test.returncode == 0, f"Browser API failed: {browser_test.stderr[-3000:]}"
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
            studio = props(owner, f"{route}/design")["studio"]
            check(
                studio["version"] == result["version"]
                and studio["publishedVersion"] == 0
                and not studio["enabled"],
                "MCP edits published or activated their theme",
            )
            check(props(public, "/")["theme"]["id"] == previous, "MCP changed the live website")
            check(
                json.loads(owner.request(f"{route}/design/status")[2])["version"]
                == result["version"],
                "The editor cannot observe an MCP draft version",
            )
            permissions_and_events(owner, public, peers[0], peers[1], connection, result["version"])
            for peer in peers:
                peer.close()
            peers.clear()
            account = store.rows(
                "admins",
                ["id", "password"],
                [("email", "=", os.environ["TEST_ADMIN_EMAIL"])],
                limit=1,
            )[0]
            for mutation, restore in (
                ({"active": 0}, {"active": 1}),
                ({"password": "invalidated-test-password"}, {"password": account["password"]}),
            ):
                store.update("admins", mutation, [("id", "=", account["id"])])
                try:
                    check(
                        public.request(endpoint(connection), extra_headers=headers)[0] == 401,
                        "An invalidated admin account retained its MCP bearer",
                    )
                finally:
                    store.update("admins", restore, [("id", "=", account["id"])])
            check(
                owner.request(f"/admin/ai/sessions/{connection['id']}", "DELETE", {})[0] == 200,
                "Could not revoke the theme's MCP session",
            )
            check(
                public.request(endpoint(connection), extra_headers=headers)[0] == 404,
                "A revoked MCP URL did not return 404",
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
                member.request(f"{route}/ai")[0] == 403,
                "A non-manager opened theme AI settings",
            )
            restricted = issue(member)
            check(
                "get_theme_design" not in tool_names(public, restricted),
                "A non-manager discovered theme editing tools",
            )
            check(
                member.request(f"{route}/export")[0] == 403,
                "A non-manager exported a private theme",
            )
        finally:
            for peer in peers:
                peer.close()
            for identifier in packages:
                owner.request(f"/admin/themes/{identifier}/uninstall", "POST", {})
            if image is not None:
                owner.delete_media(image["id"])
            store.delete("admins", [("email", "=", email)])
    print(
        "PASS Theme MCP: official legacy/modern Streamable HTTP, detailed drafts, verified images, JavaScript tools and scoped permissions",
        flush=True,
    )


if __name__ == "__main__":
    run()
