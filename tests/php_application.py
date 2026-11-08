#!/usr/bin/env python3
"""Checks the PHP build of HaxePress as it is released.

Run `make build` first. The check packages the PHP application like a
release, unpacks it into a temporary folder, creates its .env with
setup.php and serves it with PHP's built-in server from public/, as a web
server runs the front controller. It installs the site with sample content
and checks public pages, the administration, a bundled plugin, a content
save, the compiled template cache, the schedule command and MCP: a
generated link answers initialize, tools/list and a read tool, and the
signed-in page reaches its MCP tools over HTTP.
"""

import json
import os
from pathlib import Path
import re
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.parse
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tests"))

import release  # noqa: E402

# Pages answer with their props as JSON for these headers when WELL_DATA_RESPONSES=1.
DATA = {"X-Well-Data": "true", "Accept": "application/json"}


def free_port():
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        return reservation.getsockname()[1]


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"PASS {message}")


def unpack(work):
    cms = json.loads((ROOT / "cms.json").read_text())
    archive = release.php_application("0.0.0", cms, release.packages(cms), work)
    with zipfile.ZipFile(archive) as files:
        names = files.namelist()
        check(not any(name.endswith("/.env") for name in names), "the archive has no .env")
        files.extractall(work)
    return work / "haxepress-0.0.0"


def wait_for(url, server):
    for _ in range(60):
        if server.poll() is not None:
            raise AssertionError("The PHP server stopped while starting.")
        try:
            with socket.create_connection(("127.0.0.1", int(url.rsplit(":", 1)[1])), timeout=1):
                return
        except OSError:
            time.sleep(0.5)
    raise AssertionError("The PHP server did not start.")


def run(app, url):
    # Imported after TEST_URL is set: the clients read it when they load.
    from e2e import Client
    from installation import SetupClient

    password = secrets.token_urlsafe(18)
    email = "php-owner@example.test"
    setup = SetupClient(url)
    check(setup.request("/admin/install", data=True)[0] == 200, "the installer opens")
    for fields in [
        {"driver": "sqlite", "file": "cms.sqlite\n"},
        {"driver": "sqlite\n", "file": "cms.sqlite"},
    ]:
        status = setup.request("/admin/install/database", fields)[0]
        check(status == 422, f"a database setting ending in a line break is refused: {fields}")
    status, _, result = setup.request(
        "/admin/install/database", {"driver": "sqlite", "file": "cms.sqlite"}
    )
    check(status == 200 and result["verified"], "the SQLite database is verified")
    status, _, result = setup.request(
        "/admin/install/finish",
        {
            "site_name": "PHP HaxePress",
            "admin_name": "PHP Owner",
            "admin_email": email,
            "admin_password": password,
            "confirm_password": password,
            "sample_content": "1",
        },
    )
    check(status == 200 and result.get("installed"), "the installation completes")
    settings = (app / ".env").read_text()
    check(
        password not in settings and email not in settings,
        ".env keeps no administrator credentials",
    )
    check(
        (app / "data/cms.sqlite").is_file() and not list((app / "storage").rglob("*.sqlite")),
        "the database is in data/, apart from storage/",
    )

    public = Client()
    status, _, home = public.request("/")
    check(status == 200 and "PHP HaxePress" in home, "the home page renders")
    check(public.request("/about")[0] == 200, "the about page renders")
    check(public.request("/content/welcome-to-haxepress")[0] == 200, "a content page renders")
    status, _, feed = public.request("/rss.xml")
    check(status == 200 and "<rss" in feed, "the bundled RSS plugin serves its feed")
    check(public.request("/admin")[0] == 303, "the administration needs a sign-in")

    admin = Client()
    admin.request("/admin/login")
    status = admin.request("/admin/login", "POST", {"email": email, "password": password})[0]
    check(status == 303, "the owner signs in")
    for path in ["/admin", "/admin/content", "/admin/media", "/admin/themes", "/admin/plugins"]:
        check(admin.request(path)[0] == 200, f"{path} renders")
    status, _, body = admin.request(
        "/admin/settings", "POST", {"site_name": "PHP HaxePress", "home_template": "Home\n"}
    )
    check(
        status == 422 and "Choose valid homepage and presentation settings." in body,
        "a homepage template ending in a line break is refused",
    )
    article = {
        "id": "",
        "title": "Escaping on PHP",
        "slug": "escaping-on-php",
        "excerpt": 'Quotes " and <tags> & more.',
        "content": '## Notes\n\nA <b>tag</b> & "quotes" stay text.',
        "category": "",
        "status": "published",
        "image": "",
        "image_alt": "",
        "featured": "0",
        "published_at": "2026-11-03",
        "stay": "1",
        "tags": "",
    }
    status, _, body = admin.request("/admin/content/new", extra_headers=DATA)
    article["category"] = json.loads(body)["props"]["item"]["category"]
    check(admin.request("/admin/content/save", "POST", article)[0] == 303, "content saves")
    status, _, page = public.request("/content/escaping-on-php")
    check(
        status == 200 and "&lt;b&gt;tag&lt;/b&gt; &amp; &quot;quotes&quot;" in page,
        "content text is escaped",
    )

    viewed_at = visit_content_views(app, admin)
    check_forks(admin, public)
    check_cloudflare(admin)

    views = list((app / "storage/cache/views").rglob("*.php"))
    check(len(views) > 0, "compiled templates are kept as PHP files")
    check(
        all(view.read_text().split("\n", 2)[2].startswith("return array (") for view in views),
        "compiled template files hold data only",
    )
    scheduled = subprocess.run(
        ["php", "hxwell.boot.php", "schedule:run"], cwd=app, capture_output=True, text=True
    )
    check(scheduled.returncode == 0, "the schedule command runs")
    check_mcp(admin, url)
    viewed = check_content_views(app, admin, viewed_at)
    check_columns(admin, viewed)


def check_forks(admin, public):
    """Bundled themes stay with the application; their forks render and leave on their own."""
    status, _, body = admin.request("/admin/themes/theme-notebook/uninstall", "POST", {})
    check(status == 422 and "cannot be removed" in body, "a bundled theme cannot be removed")
    for theme in ["theme-notebook", "theme-simple"]:
        status, headers, _ = admin.request(f"/admin/themes/{theme}/fork", "POST", {})
        check(status == 303 and "notice=forked" in headers["location"], f"{theme} forks")
    listing = admin.request("/admin/themes")[2]
    copies = sorted(
        set(re.findall(r"/admin/themes/(theme-[a-z0-9-]+-copy-[a-z0-9]+)/fork", listing))
    )
    check(len(copies) == 2, f"both forks are listed: {copies}")
    for copy in copies:
        check(
            admin.request(f"/admin/themes/{copy}/enable", "POST", {})[0] == 303, f"{copy} activates"
        )
        status, _, home = public.request("/")
        check(status == 200 and "PHP HaxePress" in home, f"{copy} renders the home page")
        status, headers, _ = admin.request(f"/admin/themes/{copy}/download", binary=True)
        check(status == 200 and headers["content-type"] == "application/zip", f"{copy} downloads")
    check(
        admin.request("/admin/themes/theme-simple/enable", "POST", {})[0] == 303, "Simple returns"
    )
    for copy in copies:
        status = admin.request(f"/admin/themes/{copy}/uninstall", "POST", {})[0]
        check(status == 303, f"{copy} is removed")


def check_cloudflare(admin):
    """The bundled Cloudflare plugin's middleware sets the address the sign-in limit sees."""
    from e2e import Client

    plugin = "/admin/plugins/plugin-cloudflare"
    forwarded = "198.51.100.20"
    visitor = Client()

    def sign_in(address):
        visitor.request("/admin/login")
        values = {"email": "nobody@example.test", "password": "not the password"}
        headers = {"CF-Connecting-IP": address}
        return visitor.request("/admin/login", "POST", values, extra_headers=headers)[0]

    def tunnel(enabled):
        values = {"tunnel": "true" if enabled else "false"}
        status = admin.request(f"{plugin}/settings", "POST", values)[0]
        check(status == 303, f"the Cloudflare settings save: {status}")

    check(f"{plugin}/disable" in admin.request("/admin/plugins")[2], "Cloudflare is enabled")
    tunnel(True)
    for _ in range(5):
        check(sign_in(forwarded) == 401, "a forwarded sign-in fails")
    check(sign_in(forwarded) == 429, "the forwarded address is limited")
    check(sign_in("198.51.100.21") == 401, "another forwarded address has its own limit")
    tunnel(False)
    check(sign_in(forwarded) == 401, "connections from outside Cloudflare keep their address")
    tunnel(True)
    check(admin.request(f"{plugin}/disable", "POST", {})[0] == 303, "Cloudflare disables")
    check(sign_in(forwarded) == 401, "the middleware stops with the plugin")
    check(admin.request(f"{plugin}/enable", "POST", {})[0] == 303, "Cloudflare enables")
    check(sign_in(forwarded) == 429, "the middleware returns with the plugin")
    tunnel(False)


BROWSER = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/140.0 Safari/537.36"
}
VIEWED = "/content/welcome-to-haxepress"


def visit_content_views(app, admin):
    """Views of a content page; the plugins receive them once their minute has ended."""
    from e2e import Client

    cloudflare = "/admin/plugins/plugin-cloudflare/settings"
    plugin = "/admin/plugins/plugin-view-count"
    plugins = admin.request("/admin/plugins")[2]
    check(f"{plugin}/disable" in plugins, "View Count is enabled by default")
    settings = {"show_count": "false", "position": "content.after", "count_countries": "true"}
    check(admin.request(f"{plugin}/settings", "POST", settings)[0] == 303, "Countries on")

    def visit(headers, method="GET"):
        status = Client().request(VIEWED, method, extra_headers={**BROWSER, **headers})[0]
        check(status == 200, f"{method} {VIEWED} with {headers} renders")

    check(admin.request(cloudflare, "POST", {"tunnel": "true"})[0] == 303, "Tunnel on")
    visit({"CF-IPCountry": "TR"})
    visit({"CF-IPCountry": "TR"})
    visit({"CF-IPCountry": "TR"}, "HEAD")
    visit({"User-Agent": "Mozilla/5.0 (compatible; bingbot/2.0)"})
    check(admin.request(cloudflare, "POST", {"tunnel": "false"})[0] == 303, "Tunnel off")
    visit({"CF-IPCountry": "DE"})
    check(admin.request(VIEWED, extra_headers=BROWSER)[0] == 200, "a member views the page")
    lines = [
        line
        for log in (app / "storage/view-count/pending").glob("*.log")
        for line in log.read_text().splitlines()
    ]
    check(
        sorted(line.rsplit("\t", 1)[1] for line in lines) == ["TR", "TR", "UNKNOWN"],
        f"three views wait in the minute's file instead of the database: {lines}",
    )
    return time.monotonic()


def check_content_views(app, admin, visited):
    """The minute's views reach View Count's tables, by country too, through its job."""
    counts = {}
    countries = {}
    expected = {"TR": 2, "UNKNOWN": 1}
    # PHP runs due jobs after a response; the views' minute must end first.
    while time.monotonic() - visited < 200:
        status, _, body = admin.request("/admin/view-counts/data")
        if status != 200:
            break
        counts = {item["url"]: item for item in json.loads(body)["items"]}
        if VIEWED in counts:
            content = counts[VIEWED]["contentId"]
            status, _, body = admin.request(f"/admin/view-counts/countries/data?content={content}")
            if status != 200:
                break
            countries = {item["country"]: item["views"] for item in json.loads(body)["items"]}
            if counts[VIEWED]["views"] == 3 and countries == expected:
                break
        time.sleep(3)
    check(
        VIEWED in counts and counts[VIEWED]["views"] == 3,
        f"View Count counted the visitors' views once their minute ended: {counts}",
    )
    check(
        countries == expected,
        f"the country counts used CF-IPCountry only from the trusted connection: {countries}",
    )
    check(
        not list((app / "storage/view-count/pending").glob("*.log"))
        and not list((app / "storage/view-count/pending").glob("*.claimed")),
        "the handed over minute files are removed",
    )
    for page in ["/admin/view-counts", "/admin/view-counts/countries"]:
        check(admin.request(page)[0] == 200, f"{page} renders")
    return counts[VIEWED]["contentId"]


def check_columns(admin, viewed):
    """The content list's columns on PHP: the Views column, sorting by it, hiding and moving."""

    def page(path):
        status, _, body = admin.request(path, extra_headers=DATA)
        check(status == 200, f"{path} answers with its data")
        return json.loads(body)["props"]

    views = "plugin-view-count.views"
    listing = page("/admin/content")
    keys = [column["key"] for column in listing["columns"]]
    check(
        keys[0] == "title" and views in keys and keys[-1] == "updated",
        f"the list shows the default columns and View Count's: {keys}",
    )
    status, _, html = admin.request("/admin/content")
    check(status == 200 and 'class="sort-link"' in html, "the list renders sortable headings")
    ordered = page(f"/admin/content?sort={views}&dir=desc")
    check(ordered["items"][0]["id"] == viewed, "sorting by views puts the viewed item first")
    check(
        ordered["items"][0]["cells"][keys.index(views)]["text"] == "3",
        "the Views column shows the item's count",
    )
    order = [setting["key"] for setting in listing["columnSettings"]]
    data = {"order": ",".join(order), "move": "status:up"}
    for index, key in enumerate(order):
        if key != "category":
            data[f"visible_{index}"] = key
    check(admin.request("/admin/content/columns", "POST", data)[0] == 303, "the columns save")
    arranged = [column["key"] for column in page("/admin/content")["columns"]]
    check(
        arranged[:2] == ["status", "title"] and "category" not in arranged,
        f"the saved columns are moved and hidden: {arranged}",
    )
    reset = {"order": ",".join(order), "reset": "1"}
    check(admin.request("/admin/content/columns", "POST", reset)[0] == 303, "the columns reset")
    restored = [column["key"] for column in page("/admin/content")["columns"]]
    check(restored == keys, f"resetting brings the default columns back: {restored}")


MODERN = "2026-07-28"


def check_mcp(admin, url):
    """MCP on PHP, where each request runs in a new process: the server keeps no state."""
    from e2e import Client
    from validation import post_json

    status, _, body = admin.request("/admin/ai")
    check(status == 200 and json.loads(body)["websocket"] is False, "browsers reach MCP over HTTP")
    status, _, _ = post_json(admin, "/admin/ai/sessions", {"profile": "claude\n"})
    check(status == 422, "an MCP profile ending in a line break is refused")
    status, _, body = post_json(admin, "/admin/ai/sessions", {"profile": "claude"})
    check(status == 201, "an MCP link is generated")
    link = json.loads(body)
    path = urllib.parse.urlsplit(link["url"]).path
    public = Client()
    credentials = {
        "Authorization": f"Bearer {link['token']}",
        "Accept": "application/json, text/event-stream",
    }

    def rpc(message, headers=None):
        status, _, body = post_json(public, path, message, {**credentials, **(headers or {})})
        return status, json.loads(body) if body else None

    initialize = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {"name": "php-check", "version": "1.0.0"},
        },
    }
    status, reply = rpc(initialize)
    result = reply["result"]
    check(
        status == 200
        and result["serverInfo"]["name"] == "haxepress-admin"
        and result["protocolVersion"] == "2025-11-25"
        and "tools" in result["capabilities"],
        "MCP initialize answers",
    )
    status, _ = rpc({"jsonrpc": "2.0", "method": "notifications/initialized"})
    check(status == 202, "MCP accepts the initialized notification")
    status, reply = rpc({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
    names = {tool["name"] for tool in reply["result"]["tools"]}
    check(
        status == 200
        and {"list_content", "get_content", "edit_theme_design", "upload_media_image"} <= names
        and "preview_theme_design" not in names,
        "MCP tools/list returns the admin catalog without the JVM-only preview",
    )
    call = {
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {"name": "list_content", "arguments": {"collection": "entry", "query": "PHP"}},
    }
    status, reply = rpc(call)
    result = reply["result"]
    check(
        status == 200
        and not result.get("isError")
        and result["structuredContent"]["status"] == 200
        and "escaping-on-php" in json.dumps(result["structuredContent"]),
        "the list_content tool reads content through the admin routes",
    )
    call["params"]["arguments"]["collection"] = "entry\n"
    status, reply = rpc(call)
    result = reply["result"]
    check(
        status == 200
        and result.get("isError")
        and "must match pattern" in result["content"][0]["text"],
        "an MCP argument ending in a line break fails its schema pattern",
    )
    meta = {"io.modelcontextprotocol/protocolVersion": MODERN}
    discover = {"jsonrpc": "2.0", "id": 4, "method": "server/discover", "params": {"_meta": meta}}
    status, reply = rpc(discover, {"MCP-Protocol-Version": MODERN, "Mcp-Method": "server/discover"})
    check(
        status == 200 and reply["result"]["supportedVersions"] == [MODERN],
        "the 2026-07-28 revision is discovered",
    )
    status, _, _ = public.request(path, extra_headers=credentials)
    check(status == 405, "GET has no event stream and answers 405")
    browser = {"jsonrpc": "2.0", "id": 5, "method": "tools/list", "params": {"_meta": meta}}
    status, _, body = post_json(admin, "/admin/ai/ws", browser, {"Origin": url})
    tools = json.loads(body)["result"]["tools"] if status == 200 else []
    check(
        any(tool["name"] == "set_content_cover" for tool in tools),
        "the signed-in page's MCP messages work over HTTP",
    )
    check(
        admin.request(f"/admin/ai/sessions/{link['id']}", "DELETE", {})[0] == 200,
        "the MCP link is revoked",
    )
    status, _ = rpc({"jsonrpc": "2.0", "id": 6, "method": "tools/list"})
    check(status == 404, "a revoked MCP link stops working")


def main():
    if shutil.which("php") is None:
        raise SystemExit("PHP 8.1 or later is required.")
    with tempfile.TemporaryDirectory(prefix="haxepress-php-") as name:
        app = unpack(Path(name))
        subprocess.run(["php", "setup.php"], cwd=app, check=True)
        port = free_port()
        url = f"http://127.0.0.1:{port}"
        # MCP links and trusted browser origins use the site's own address.
        settings = re.sub(r"(?m)^APP_URL=.*$", f"APP_URL={url}", (app / ".env").read_text())
        (app / ".env").write_text(f"{settings}\nWELL_DATA_RESPONSES=1\n")
        os.environ["TEST_URL"] = url
        log = open(app / "server.log", "w")
        server = subprocess.Popen(
            ["php", "-S", f"127.0.0.1:{port}", "index.php"],
            cwd=app / "public",
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        try:
            wait_for(url, server)
            run(app, url)
        except BaseException:
            log.flush()
            print((app / "server.log").read_text()[-4000:])
            raise
        finally:
            server.terminate()
            server.wait()
            log.close()
    print("PHP application checks passed.")


if __name__ == "__main__":
    main()
