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
from migrations import prepare as prepare_migrations, verify as verify_migrations
from fixture_store import FixtureStore, CONTENT_COLUMNS, TEST_BINARY
from build import build
from e2e import InertiaPageParser

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_ROOT = Path(os.environ.get("CMS_TEST_PUBLIC_PATH", ROOT / "public"))
SSR_BINARY = Path(os.environ.get("CMS_TEST_SSR_PATH", ROOT / "bootstrap/ssr/ssr.js"))
parser = argparse.ArgumentParser(description="Run isolated JVM integration suites.")
parser.add_argument(
    "--only",
    choices=[
        "e2e",
        "installation",
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
        "theme_mcp",
        "websocket_lifecycle",
        "builtin_theme",
        "cms_content",
        "cms_management",
        "cms_structure",
        "cms_lifecycle",
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
                if "<main" not in body or "data-cms-site" not in body:
                    raise RuntimeError("Inertia SSR did not render the homepage.")
                return body
        except (OSError, http.client.HTTPException):
            pass
        time.sleep(0.2)
    raise RuntimeError("Crossbyte did not become ready within 90 seconds.")


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def verify_shutdown(process, log):
    snapshot = subprocess.check_output(["ps", "-axo", "pid=,ppid=,comm="], text=True)
    children = []
    for line in snapshot.splitlines():
        fields = line.split(maxsplit=2)
        if len(fields) == 3 and fields[1] == str(process.pid) and Path(fields[2]).name == "node":
            children.append(int(fields[0]))
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
            raise RuntimeError("The site left its MCP child process running after shutdown.")
    log.flush()
    log.seek(0)
    shutdown_log = log.read()
    if (
        "ConcurrentModificationException" in shutdown_log
        or "Plugin shutdown failed:" in shutdown_log
    ):
        raise RuntimeError("Plugin destruction failed during graceful JVM shutdown.")
    print("PASS Graceful JVM shutdown destroys all running plugin instances", flush=True)
    if children:
        print("PASS Site shutdown terminates its hosted MCP process", flush=True)


with tempfile.TemporaryDirectory(prefix="haxepress-test-") as name:
    work = Path(name)
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        ssr_port = reservation.getsockname()[1]
    for folder in ("sessions", "cache"):
        (work / "storage" / folder).mkdir(parents=True, exist_ok=True)
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
        "APP_URL": "http://127.0.0.1:" + str(port),
        "HOST": "127.0.0.1",
        "PORT": str(port),
        "MAX_CONNECTIONS": "10000",
        "WORKERS": "16",
        "DB_DRIVER": "sqlite",
        "DB_PATH": str(work / "storage/cms.sqlite"),
        "SESSION_PATH": str(work / "storage/sessions"),
        "CACHE_PATH": str(work / "storage/cache"),
        "ADMIN_EMAIL": "integration-admin@example.com",
        "ADMIN_PASSWORD": password,
        "TEST_GUARD_PATH": str(work / "query-guard.json"),
    }
    values.update(
        VITE_USE_BUILD="true",
        VITE_INCLUDE_PAGE_ENTRY="false",
        INERTIA_SSR_ENABLED="true",
        INERTIA_SSR_URL="http://127.0.0.1:" + str(ssr_port) + "/render",
        INERTIA_SSR_TIMEOUT="3",
    )
    (work / ".env").write_text("".join(key + "=" + value + "\n" for key, value in values.items()))
    (work / ".env").chmod(0o600)
    with (work / "server.log").open("w+") as log:
        ssr_env = os.environ.copy()
        ssr_env["INERTIA_SSR_PORT"] = str(ssr_port)
        ssr_env["CMS_STORAGE_PATH"] = str(work / "storage")
        ssr = subprocess.Popen(
            ["node", str(SSR_BINARY)],
            cwd=ROOT,
            env=ssr_env,
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        ssr_deadline = time.monotonic() + 45
        while time.monotonic() < ssr_deadline and ssr.poll() is None:
            try:
                probe = http.client.HTTPConnection("127.0.0.1", ssr_port, timeout=0.5)
                probe.request("GET", "/health")
                ready = probe.getresponse()
                ready.read()
                probe.close()
                if ready.status == 200:
                    break
            except OSError:
                time.sleep(0.1)
        else:
            stop(ssr)
            log.flush()
            log.seek(0)
            print(log.read()[-12000:], file=sys.stderr)
            raise RuntimeError("Inertia SSR process failed to start within 45 seconds.")
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
            )
            suites = (
                [arguments.only]
                if arguments.only
                else [
                    "e2e",
                    "installation",
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
                    "theme_mcp",
                    "websocket_lifecycle",
                    "builtin_theme",
                    "cms_content",
                    "cms_management",
                    "cms_structure",
                    "cms_lifecycle",
                    "plugin_database",
                    "media_dependencies",
                    "site_identity",
                    "i18n",
                ]
            )
            for suite in suites:
                result = subprocess.run(
                    [sys.executable, str(ROOT / "tests" / (suite + ".py"))], cwd=ROOT, env=env
                )
                if result.returncode:
                    raise RuntimeError(suite + " integration suite failed.")
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
            rendered = InertiaPageParser()
            rendered.feed(body)
            if len(rendered.pages) != 1 or rendered.pages[0]["props"]["count"] != 7:
                raise RuntimeError("Initial data was duplicated or lost after restart.")
            images = list((work / "storage/media").glob("*.jpg"))
            if not images:
                raise RuntimeError("Uploaded image was not saved in storage/media.")
            client = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            client.request("GET", "/media/" + images[0].name)
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
            verifier = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            verifier.request(
                "GET", "/admin/login", headers={"X-Inertia": "true", "Accept": "application/json"}
            )
            verified = verifier.getresponse()
            assert json.loads(verified.read())["props"]["pluginRestartRequired"] is False
            verifier.close()
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
            client = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            client.request(
                "GET", "/content", headers={"X-Inertia": "true", "Accept": "application/json"}
            )
            response = client.getresponse()
            payload = response.read().decode()
            client.close()
            if response.status != 200 or "Legacy notebook" not in payload:
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
            stop(ssr)
print("All fresh-install, upload, and HTTP integration checks passed.", flush=True)
