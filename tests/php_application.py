#!/usr/bin/env python3
"""Checks the PHP build of HaxePress as it is released.

Run `make build` first. The check packages the PHP application like a
release, unpacks it into a temporary folder, creates its .env with
setup.php and serves it with PHP's built-in server from public/, as a web
server runs the front controller. It installs the site with sample content
and checks public pages, the administration, a bundled plugin, a content
save, the compiled template cache and the schedule command.
"""

import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time
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


def main():
    if shutil.which("php") is None:
        raise SystemExit("PHP 8.1 or later is required.")
    with tempfile.TemporaryDirectory(prefix="haxepress-php-") as name:
        app = unpack(Path(name))
        subprocess.run(["php", "setup.php"], cwd=app, check=True)
        with open(app / ".env", "a") as settings:
            settings.write("\nWELL_DATA_RESPONSES=1\n")
        port = free_port()
        url = f"http://127.0.0.1:{port}"
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
