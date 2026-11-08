#!/usr/bin/env python3
"""Test a fresh Schema/Eloquent database in an isolated Crossbyte process."""

import base64
import argparse
import http.client
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile
import time
from content_cache import stamps, verify as verify_content_cache
from example_upgrade import (
    prepare as prepare_example_upgrade,
    verify as verify_example_upgrade,
    verify_unchanged as verify_example_unchanged,
)
from migrations import prepare as prepare_migrations, verify as verify_migrations
from fixture_store import FixtureStore, CONTENT_COLUMNS, TEST_BINARY
from build import build

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_ROOT = Path(os.environ.get("CMS_TEST_PUBLIC_PATH", ROOT / "public"))
parser = argparse.ArgumentParser(description="Run isolated JVM integration suites.")
parser.add_argument(
    "--only",
    choices=[
        "e2e",
        "installation",
        "site_backup",
        "backup_roundtrip",
        "auth",
        "validation",
        "native_api",
        "scoped_queries",
        "cms",
        "cms_packages",
        "theme_customization",
        "theme_builder",
        "composable_themes",
        "easy_builder",
        "theme_export",
        "theme_assets",
        "theme_forks",
        "theme_mcp",
        "admin_mcp",
        "websocket_lifecycle",
        "builtin_theme",
        "cms_content",
        "cms_management",
        "cms_structure",
        "cms_lifecycle",
        "cloudflare",
        "view_count",
        "view_count_countries",
        "plugin_database",
        "media_dependencies",
        "site_identity",
        "i18n",
    ],
)
parser.add_argument("--skip-build", action="store_true")
arguments = parser.parse_args()
BINARY = TEST_BINARY
if not arguments.skip_build:
    build()
    subprocess.run(
        [sys.executable, str(ROOT / "scripts/build_packages.py"), "--application", str(BINARY)],
        cwd=ROOT,
        check=True,
    )
COMMAND = ["java", "--enable-native-access=ALL-UNNAMED", "-jar", str(BINARY), "start"]
if not BINARY.exists():
    raise SystemExit("Run make build first.")


def wait_ready(port, process):
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("Crossbyte process exited before startup.")
        try:
            client = http.client.HTTPConnection("127.0.0.1", port, timeout=1)
            client.request("GET", "/")
            response = client.getresponse()
            body = response.read().decode()
            client.close()
            if response.status == 200:
                if "<main" not in body or "data-cms-site" not in body or "data-page=" in body:
                    raise RuntimeError("The server did not render the homepage HTML.")
                return body
        except (OSError, http.client.HTTPException):
            pass
        time.sleep(0.2)
    raise RuntimeError("Crossbyte did not become ready within 90 seconds.")


def page_data(port, path):
    client = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        client.request("GET", path, headers={"X-Well-Data": "true", "Accept": "application/json"})
        response = client.getresponse()
        payload = response.read().decode()
    finally:
        client.close()
    if response.status != 200 or response.getheader("X-Well-Data") != "true":
        raise RuntimeError(f"{path} did not return page data: {str(response.status)}")
    return json.loads(payload)


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def child_processes(process):
    """The site's direct child processes, by process ID and executable name."""
    snapshot = subprocess.check_output(["ps", "-axo", "pid=,ppid=,comm="], text=True)
    children = []
    for line in snapshot.splitlines():
        fields = line.split(maxsplit=2)
        if len(fields) == 3 and fields[1] == str(process.pid):
            children.append((int(fields[0]), Path(fields[2]).name))
    return children


def verify_shutdown(process, log):
    processes = child_processes(process)
    if any(name == "node" for _, name in processes):
        raise RuntimeError("The site started a Node.js process.")
    # The MCP preview tool's headless browser is the only process the site starts.
    children = [pid for pid, name in processes if "chrom" in name.lower()]
    stop(process)
    deadline = time.monotonic() + 3
    for child in children:
        while time.monotonic() < deadline:
            try:
                os.kill(child, 0)
            except ProcessLookupError:
                break
            time.sleep(0.02)
        else:
            os.kill(child, 15)
            raise RuntimeError("The site left its preview browser running after shutdown.")
    log.flush()
    log.seek(0)
    shutdown_log = log.read()
    if (
        "ConcurrentModificationException" in shutdown_log
        or "Plugin shutdown failed:" in shutdown_log
    ):
        raise RuntimeError("Plugin destruction failed during graceful JVM shutdown.")
    print("PASS Graceful JVM shutdown destroys all running plugin instances", flush=True)
    print("PASS The site serves MCP without a Node.js process", flush=True)
    if children:
        print("PASS Site shutdown stops the MCP preview browser", flush=True)


with tempfile.TemporaryDirectory(prefix="haxepress-test-") as name:
    work = Path(name)
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    for folder in ("sessions", "cache"):
        (work / "storage" / folder).mkdir(parents=True, exist_ok=True)
    (work / "data").mkdir()
    for folder in ("public", "database"):
        source = PUBLIC_ROOT if folder == "public" else ROOT / folder
        (work / folder).symlink_to(source, target_is_directory=True)
    password = secrets.token_urlsafe(18)
    values = {
        "APP_NAME": "haxepress_test",
        "APP_INSTALLED": "true",
        "APP_ENV": "development",
        "APP_KEY": base64.b64encode(secrets.token_bytes(32)).decode(),
        "APP_DEBUG": "false",
        "APP_URL": f"http://127.0.0.1:{str(port)}",
        "HOST": "127.0.0.1",
        "PORT": str(port),
        "MAX_CONNECTIONS": "10000",
        "WORKERS": "16",
        "DB_DRIVER": "sqlite",
        "DB_PATH": str(work / "data/cms.sqlite"),
        "SESSION_PATH": str(work / "storage/sessions"),
        "CACHE_PATH": str(work / "storage/cache"),
        "ADMIN_EMAIL": "integration-admin@example.com",
        "ADMIN_PASSWORD": password,
        "TEST_GUARD_PATH": str(work / "query-guard.json"),
    }
    values.update(WELL_DATA_RESPONSES="1")
    (work / ".env").write_text("".join(f"{key}={value}\n" for key, value in values.items()))
    (work / ".env").chmod(0o600)
    with (work / "server.log").open("w+") as log:
        process = subprocess.Popen(COMMAND, cwd=work, stdout=log, stderr=subprocess.STDOUT)
        fixtures = None
        try:
            wait_ready(port, process)
            print("PASS Fresh HxWell Schema creation and Eloquent seeding", flush=True)
            fixtures = FixtureStore(work)
            if arguments.only is None:
                verify_content_cache(port, fixtures, work / "storage/cache")
            env = os.environ.copy()
            env.update(
                TEST_URL=values["APP_URL"],
                TEST_ADMIN_EMAIL=values["ADMIN_EMAIL"],
                TEST_ADMIN_PASSWORD=password,
                TEST_DB_PATH=values["DB_PATH"],
                TEST_CACHE_PATH=str(work / "storage/cache"),
                TEST_STORAGE_PATH=str(work / "storage"),
            )
            suites = (
                [arguments.only]
                if arguments.only
                else [
                    "e2e",
                    "installation",
                    "site_backup",
                    "auth",
                    "validation",
                    "native_api",
                    "scoped_queries",
                    "cms",
                    "cms_packages",
                    "theme_customization",
                    "theme_builder",
                    "composable_themes",
                    "easy_builder",
                    "theme_export",
                    "theme_assets",
                    "theme_forks",
                    "theme_mcp",
                    "admin_mcp",
                    "websocket_lifecycle",
                    "builtin_theme",
                    "cms_content",
                    "cms_management",
                    "cms_structure",
                    "cms_lifecycle",
                    "cloudflare",
                    "view_count",
                    "view_count_countries",
                    "plugin_database",
                    "media_dependencies",
                    "site_identity",
                    "i18n",
                ]
            )
            for suite in suites:
                result = subprocess.run(
                    [sys.executable, str(ROOT / "tests" / (f"{suite}.py"))], cwd=ROOT, env=env
                )
                if result.returncode:
                    raise RuntimeError(f"{suite} integration suite failed.")
            if arguments.only is not None:
                verify_shutdown(process, log)
                sys.exit(0)
            wait_ready(port, process)
            verify_shutdown(process, log)
            cache_before = stamps(work / "storage/cache")
            categories_before = list(fixtures.scan("categories", ["id", "name"]))
            content_before = list(fixtures.scan("items", CONTENT_COLUMNS))
            process = subprocess.Popen(COMMAND, cwd=work, stdout=log, stderr=subprocess.STDOUT)
            body = wait_ready(port, process)
            if stamps(work / "storage/cache") != cache_before:
                raise RuntimeError(
                    "Content caches were unnecessarily discarded or rewritten after restart."
                )
            home = page_data(port, "/")
            if home["component"] != "Home" or home["props"]["count"] != 7:
                raise RuntimeError("Initial data was duplicated or lost after restart.")
            images = list((work / "storage/media").glob("*.jpg"))
            if not images:
                raise RuntimeError("Uploaded image was not saved in storage/media.")
            client = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            client.request("GET", f"/media/{images[0].name}")
            media = client.getresponse()
            media_body = media.read()
            client.close()
            if media.status != 200 or media_body != images[0].read_bytes():
                raise RuntimeError("Uploaded image was lost after restart.")
            if list(fixtures.scan("categories", ["id", "name"])) != categories_before:
                raise RuntimeError(
                    "Categories changed or deleted categories returned after restart."
                )
            if list(fixtures.scan("items", CONTENT_COLUMNS)) != content_before:
                raise RuntimeError("Content changed after restart.")
            print(
                "PASS Persistent database, content cache and idempotent boot after Crossbyte restart",
                flush=True,
            )
            assert page_data(port, "/admin/login")["props"]["pluginRestartRequired"] is False
            stop(process)
            # Reproduce the previous release: named content categories, no category table.
            fixtures.call("drop_categories")
            fixtures.delete("settings", [("key", "=", "managed_categories_v1")])
            fixtures.update("items", {"category": "Legacy notebook"}, [("status", "=", "draft")])
            legacy_content = list(fixtures.scan("items", CONTENT_COLUMNS))
            process = subprocess.Popen(COMMAND, cwd=work, stdout=log, stderr=subprocess.STDOUT)
            wait_ready(port, process)
            if list(fixtures.scan("items", CONTENT_COLUMNS)) != legacy_content:
                raise RuntimeError("Category migration changed existing content item data.")
            if fixtures.count("categories", [("name", "=", "Legacy notebook")]) != 1:
                raise RuntimeError(
                    "Category migration lost a category on an existing content item."
                )
            if fixtures.count("categories") != 6:
                raise RuntimeError(
                    "Category migration did not preserve the five original categories."
                )
            print(
                "PASS Migration of existing content item categories without content or edit-date changes",
                flush=True,
            )
            if "Legacy notebook" not in json.dumps(page_data(port, "/content")):
                raise RuntimeError("Category migration left a stale content cache.")
            print("PASS Data migrations invalidate affected content caches", flush=True)
            stop(process)
            expected_migrations = prepare_migrations(fixtures)
            process = subprocess.Popen(COMMAND, cwd=work, stdout=log, stderr=subprocess.STDOUT)
            wait_ready(port, process)
            verify_migrations(fixtures, expected_migrations)
            print(
                "PASS Multi-batch ORM migrations: 205 extra content, 105 distinct categories, preserved content/dates and existing reading metadata",
                flush=True,
            )
            stop(process)
            process = subprocess.Popen(COMMAND, cwd=work, stdout=log, stderr=subprocess.STDOUT)
            wait_ready(port, process)
            verify_migrations(fixtures, expected_migrations)
            print("PASS Repeated startup preserves completed ORM migrations", flush=True)
            stop(process)
            expected_example = prepare_example_upgrade(fixtures, work)
            process = subprocess.Popen(COMMAND, cwd=work, stdout=log, stderr=subprocess.STDOUT)
            wait_ready(port, process)
            example_directory = verify_example_upgrade(fixtures, work, expected_example)
            stop(process)
            process = subprocess.Popen(COMMAND, cwd=work, stdout=log, stderr=subprocess.STDOUT)
            wait_ready(port, process)
            verify_example_unchanged(fixtures, example_directory)
            print(
                "PASS Startup replaces a bundled theme whose shipped archive changed under the same version, keeping its settings, reinstalls a removed one, and leaves them alone afterwards",
                flush=True,
            )
            stop(process)
            # An active theme built for the former browser renderer, as an older release left it.
            legacy_manifest = {
                "apiVersion": 2,
                "cmsVersion": "2.10.0",
                "kind": "theme",
                "slug": "legacy-renderer",
                "name": "Legacy renderer",
                "version": "1.0.0",
                "author": "Package author",
                "layout": "legacy",
                "assets": {"renderer": "theme.mjs", "stylesheet": "site.css"},
            }
            fixtures.update("cms_packages", {"enabled": 0}, [("kind", "=", "theme")])
            fixtures.create(
                "cms_packages",
                [
                    {
                        "id": "theme-legacy-renderer",
                        "kind": "theme",
                        "slug": "legacy-renderer",
                        "name": "Legacy renderer",
                        "name_key": "",
                        "version": "1.0.0",
                        "description": "",
                        "author": "Package author",
                        "last_error": "",
                        "restart_required": 0,
                        "setting_count": 0,
                        "directory": "theme-legacy-renderer-1-0-0",
                        "manifest": json.dumps(legacy_manifest),
                        "enabled": 1,
                        "settings": "{}",
                        "installed_at": "2026-01-01 00:00:00",
                        "updated_at": "2026-01-01 00:00:00",
                    }
                ],
            )
            process = subprocess.Popen(COMMAND, cwd=work, stdout=log, stderr=subprocess.STDOUT)
            wait_ready(port, process)
            if fixtures.count("cms_packages", [("id", "=", "theme-legacy-renderer")]) != 0:
                raise RuntimeError("A theme for the former browser renderer was kept.")
            active = fixtures.rows(
                "cms_packages", ["id"], [("kind", "=", "theme"), ("enabled", "=", 1)]
            )
            if [row["id"] for row in active] != ["theme-simple"]:
                raise RuntimeError("The built-in theme did not replace a removed renderer theme.")
            if page_data(port, "/")["props"]["theme"]["id"] != "theme-simple":
                raise RuntimeError("The site still renders a removed renderer theme.")
            print(
                "PASS Startup removes themes built for the former browser renderer; the built-in theme takes over",
                flush=True,
            )
            stop(process)
            # Early SQLite releases limited content status to draft and published.
            if fixtures.call("legacy_status_check") is not False:
                raise RuntimeError("The legacy content status constraint was not reproduced.")
            trashed, scheduled = [row["id"] for row in fixtures.rows("items", ["id"], limit=2)]
            try:
                fixtures.update("items", {"status": "trash"}, [("id", "=", trashed)])
            except RuntimeError as error:
                if "CHECK" not in str(error):
                    raise
            else:
                raise RuntimeError("The legacy content status constraint accepted a trashed item.")
            legacy_content = list(fixtures.scan("items", CONTENT_COLUMNS))
            process = subprocess.Popen(COMMAND, cwd=work, stdout=log, stderr=subprocess.STDOUT)
            wait_ready(port, process)
            if fixtures.call("portable_definition", table="content_items") is not True:
                raise RuntimeError("Startup kept the legacy content status constraint.")
            if list(fixtures.scan("items", CONTENT_COLUMNS)) != legacy_content:
                raise RuntimeError("The content status migration changed content item data.")
            fixtures.update("items", {"status": "trash"}, [("id", "=", trashed)])
            fixtures.update("items", {"status": "scheduled"}, [("id", "=", scheduled)])
            print(
                "PASS Startup lifts the legacy content status constraint without changing content",
                flush=True,
            )
            # The backup round trip runs here, on the upgraded database with every status.
            result = subprocess.run(
                [sys.executable, str(ROOT / "tests/backup_roundtrip.py")], cwd=ROOT, env=env
            )
            if result.returncode:
                raise RuntimeError("backup_roundtrip integration suite failed.")
        except Exception:
            log.flush()
            log.seek(0)
            failure_log = log.read()
            output = ROOT / "outputs/integration-failure.log"
            output.parent.mkdir(exist_ok=True)
            output.write_text(failure_log)
            output.chmod(0o600)
            print(failure_log[-12000:], file=sys.stderr)
            raise
        finally:
            if fixtures is not None:
                fixtures.close()
            stop(process)
print("All fresh-install, upload, and HTTP integration checks passed.", flush=True)
