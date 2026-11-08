"""Verify the bundled Cloudflare plugin and the plugin middleware it adds.

The site sees a request's address in the sign-in limit, which allows five
failed attempts per address. The tests reach the site from 127.0.0.1, which
is not a Cloudflare address, so the plugin's Cloudflare Tunnel setting is
what lets these connections forward a visitor's address.
"""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from e2e import Client, check
from fixture_store import FixtureStore

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from plugin_build import compiler, environment

PLUGIN = "/admin/plugins/plugin-cloudflare"
HEADER = "CF-Connecting-IP"
LIMITED = "198.51.100.10"
OTHER = "198.51.100.11"
IPV6 = "2001:db8::10"


def check_addresses():
    """The address parsing and Cloudflare ranges, in the Haxe interpreter."""
    result = subprocess.run(
        [
            str(compiler()),
            "-cp",
            str(ROOT / "examples/plugins/cloudflare/src"),
            "-cp",
            str(ROOT / "tests/haxe/cloudflare"),
            "-main",
            "CloudflareAddressesCheck",
            "--interp",
        ],
        cwd=ROOT,
        env=environment(),
        capture_output=True,
        text=True,
    )
    check(
        result.returncode == 0, f"Cloudflare address checks failed:\n{result.stdout}{result.stderr}"
    )
    print(result.stdout.strip(), flush=True)


def sign_in(client, address=None):
    """A failed sign-in, optionally forwarding `address`; returns the status."""
    client.request("/admin/login")
    headers = {HEADER: address} if address is not None else None
    values = {"email": "nobody@example.test", "password": "not the password"}
    return client.request("/admin/login", "POST", values, extra_headers=headers)[0]


def configure(owner, tunnel):
    owner.request(f"{PLUGIN}/settings")
    value = "true" if tunnel else "false"
    status = owner.request(f"{PLUGIN}/settings", "POST", {"tunnel": value})[0]
    check(status == 303, f"Could not save the Cloudflare settings: {status}")


def attempt_key(address):
    return hashlib.sha256(f"login:{address}".encode()).hexdigest()


def run():
    check_addresses()
    owner = Client()
    visitor = Client()
    owner.request("/admin/login")
    credentials = {
        "email": os.environ["TEST_ADMIN_EMAIL"],
        "password": os.environ["TEST_ADMIN_PASSWORD"],
    }
    check(owner.request("/admin/login", "POST", credentials)[0] == 303, "Cloudflare owner login")
    with FixtureStore.from_environment() as fixtures:
        try:
            installed = fixtures.rows(
                "cms_packages", ["enabled", "settings"], [("id", "=", "plugin-cloudflare")], limit=1
            )
            check(len(installed) == 1, "The Cloudflare plugin is not installed with the site")
            check(installed[0]["enabled"] == 1, "The Cloudflare plugin is not enabled by default")
            plugins = owner.request("/admin/plugins")[2]
            check(
                f"{PLUGIN}/disable" in plugins,
                "The plugin list does not offer to disable Cloudflare",
            )
            check(
                f"{PLUGIN}/uninstall" not in plugins, "The bundled Cloudflare plugin can be removed"
            )

            configure(owner, True)
            for attempt in range(5):
                status = sign_in(visitor, LIMITED)
                check(status == 401, f"Forwarded sign-in {attempt + 1} returned {status}")
            check(sign_in(visitor, LIMITED) == 429, "The forwarded address was not limited")
            check(sign_in(visitor, OTHER) == 401, "Another forwarded address shared the limit")
            check(sign_in(visitor, IPV6) == 401, "An IPv6 forwarded address shared the limit")
            check(
                fixtures.count("login_attempts", [("key", "=", attempt_key(IPV6))]) == 1,
                "The forwarded IPv6 address was not used",
            )
            print(
                "PASS Cloudflare Tunnel connections use the address in CF-Connecting-IP", flush=True
            )

            configure(owner, False)
            check(
                sign_in(visitor, LIMITED) == 401,
                "A connection from outside Cloudflare could choose its address",
            )
            configure(owner, True)
            check(sign_in(visitor, LIMITED) == 429, "Saved settings did not reach the middleware")
            check(
                sign_in(visitor, f"{LIMITED}, {OTHER}") == 401,
                "A header with two addresses was used",
            )
            print(
                "PASS Other connections and malformed values keep the connection's address",
                flush=True,
            )

            check(owner.request(f"{PLUGIN}/disable", "POST", {})[0] == 303, "disable Cloudflare")
            check(
                sign_in(visitor, LIMITED) == 401, "The middleware remained after the plugin stopped"
            )
            check(owner.request(f"{PLUGIN}/enable", "POST", {})[0] == 303, "enable Cloudflare")
            check(sign_in(visitor, LIMITED) == 429, "The middleware did not return with the plugin")
            print(
                "PASS Plugin middleware is added on creation and removed when the plugin stops",
                flush=True,
            )

            # PHP builds before this release stored settings as a Map's storage.
            configure(owner, False)
            legacy = json.dumps({"data": {"tunnel": "true"}})
            fixtures.update(
                "cms_packages", {"settings": legacy}, [("id", "=", "plugin-cloudflare")]
            )
            check(owner.request(f"{PLUGIN}/disable", "POST", {})[0] == 303, "disable Cloudflare")
            check(owner.request(f"{PLUGIN}/enable", "POST", {})[0] == 303, "enable Cloudflare")
            check(
                sign_in(visitor, LIMITED) == 429,
                "Settings stored by earlier PHP builds did not reach the plugin",
            )
            print("PASS Settings stored by earlier PHP builds are read", flush=True)
        finally:
            owner.request(f"{PLUGIN}/enable", "POST", {})
            configure(owner, False)
            for address in [LIMITED, OTHER, IPV6, "127.0.0.1"]:
                fixtures.delete("login_attempts", [("key", "=", attempt_key(address))])
            stored = fixtures.rows(
                "cms_packages", ["settings"], [("id", "=", "plugin-cloudflare")], limit=1
            )
            check(
                json.loads(stored[0]["settings"]).get("tunnel", "false") == "false",
                "The Cloudflare settings were not restored",
            )


if __name__ == "__main__":
    run()
