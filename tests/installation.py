"""Fresh installs require a trusted socket peer and write private, literal configuration."""

import base64
import http.client
import http.cookies
import json
import os
from pathlib import Path
import secrets
import shutil
import sys
import socket
import stat
import subprocess
import tempfile
import time
import urllib.parse

from e2e import check, InertiaPageParser
from fixture_store import FixtureStore, TEST_BINARY

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = Path(os.environ.get("CMS_TEST_PUBLIC_PATH", ROOT / "public"))
SSR = Path(os.environ.get("CMS_TEST_SSR_PATH", ROOT / "bootstrap/ssr/ssr.js"))


def port():
    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0))
        return reserved.getsockname()[1]


class SetupClient:
    def __init__(self, address):
        self.address = urllib.parse.urlsplit(address)
        self.cookies = {}
        self.csrf = ""

    def request(self, path, values=None, headers=None, csrf=True, inertia=False):
        fields = {"Accept": "application/json"}
        if self.cookies:
            fields["Cookie"] = "; ".join(key + "=" + value for key, value in self.cookies.items())
        if inertia:
            fields["X-Inertia"] = "true"
        body = None
        if values is not None:
            body = json.dumps(values)
            fields["Content-Type"] = "application/json"
            if csrf:
                fields["X-CSRF-TOKEN"] = self.csrf
        fields.update(headers or {})
        connection = http.client.HTTPConnection(
            self.address.hostname, self.address.port, timeout=35
        )
        try:
            connection.request("GET" if values is None else "POST", path, body, fields)
            response = connection.getresponse()
            payload = response.read().decode()
            for key, value in response.getheaders():
                if key.lower() == "set-cookie":
                    parsed = http.cookies.SimpleCookie()
                    parsed.load(value)
                    for name, item in parsed.items():
                        self.cookies[name] = item.value
            normalized = {key.lower(): value for key, value in response.getheaders()}
            if "application/json" in normalized.get("content-type", ""):
                data = json.loads(payload) if payload else {}
                if inertia and data.get("props", {}).get("csrfToken"):
                    self.csrf = data["props"]["csrfToken"]
            else:
                data = payload
                parser = InertiaPageParser()
                parser.feed(payload)
                if parser.pages:
                    self.csrf = parser.pages[0]["props"].get("csrfToken") or self.csrf
            return response.status, normalized, data
        finally:
            connection.close()


class SetupServer:
    def __init__(self, work, trusted):
        self.work = work
        self.port = port()
        self.ssr_port = port()
        self.url = "http://127.0.0.1:" + str(self.port)
        work.chmod(0o700)
        (work / "storage").mkdir()
        (work / "public").symlink_to(PUBLIC, target_is_directory=True)
        (work / "database").symlink_to(ROOT / "database", target_is_directory=True)
        values = {
            "APP_NAME": "haxepress_test",
            "APP_ENV": "development",
            "APP_INSTALLED": "false",
            "APP_KEY": base64.b64encode(secrets.token_bytes(32)).decode(),
            "APP_URL": self.url,
            "HOST": "127.0.0.1",
            "PORT": str(self.port),
            "DB_DRIVER": "sqlite",
            "DB_PATH": str(work / "storage/untouched.sqlite"),
            "STORAGE_PATH": str(work / "storage"),
            "CACHE_PATH": str(work / "storage/cache"),
            "SESSION_PATH": str(work / "storage/sessions"),
            "VITE_USE_BUILD": "true",
            "VITE_INCLUDE_PAGE_ENTRY": "false",
            "INERTIA_SSR_ENABLED": "true",
            "INERTIA_SSR_URL": "http://127.0.0.1:" + str(self.ssr_port) + "/render",
            "INERTIA_SSR_TIMEOUT": "3",
            "UNRELATED_SETTING": "preserved",
        }
        if trusted is not None:
            values["INSTALL_TRUSTED_IPS"] = trusted
        (work / ".env").write_text(
            "".join(key + "=" + value + "\n" for key, value in values.items())
        )
        (work / ".env").chmod(0o600)
        self.log = (work / "runtime.log").open("w+")
        self.renderer = subprocess.Popen(
            ["node", str(SSR)],
            cwd=ROOT,
            env={
                **os.environ,
                "INERTIA_SSR_PORT": str(self.ssr_port),
                "CMS_STORAGE_PATH": str(work / "storage"),
            },
            stdout=self.log,
            stderr=subprocess.STDOUT,
        )
        self.process = None
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline and self.renderer.poll() is None:
            try:
                connection = http.client.HTTPConnection("127.0.0.1", self.ssr_port, timeout=1)
                connection.request("GET", "/health")
                response = connection.getresponse()
                response.read()
                connection.close()
                if response.status == 200:
                    break
            except OSError:
                pass
            time.sleep(0.1)
        else:
            self.stop(self.renderer)
            self.log.close()
            raise RuntimeError("The installation SSR process did not become ready.")
        self.start()

    def start(self):
        self.process = subprocess.Popen(
            ["java", "--enable-native-access=ALL-UNNAMED", "-jar", str(TEST_BINARY), "start"],
            cwd=self.work,
            stdout=self.log,
            stderr=subprocess.STDOUT,
        )
        client = SetupClient(self.url)
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                break
            try:
                status, _, data = client.request("/admin/install", inertia=True)
                if status in (200, 403, 404):
                    return
            except (OSError, http.client.HTTPException):
                pass
            time.sleep(0.1)
        self.log.flush()
        raise RuntimeError(
            "Installer did not start: " + (self.work / "runtime.log").read_text()[-3000:]
        )

    @staticmethod
    def stop(process):
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

    def close(self):
        self.stop(self.process)
        self.stop(self.renderer)
        self.log.close()
        if sys.exc_info()[0] is not None:
            failure = ROOT / "outputs/installer/failure" / self.work.name
            failure.mkdir(parents=True, exist_ok=True)
            failure.chmod(0o700)
            shutil.copytree(self.work, failure, dirs_exist_ok=True, symlinks=True)


def verify_mysql(mysql_port, mysql_work):
    name = "haxepress_install_" + secrets.token_hex(5)
    classpath = str(TEST_BINARY) + os.pathsep + str(TEST_BINARY.parent / "lib/*")
    command = ["java", "-cp", classpath, "fixtures.MysqlSetupFixture", str(mysql_port), name]
    subprocess.run(command, cwd=mysql_work, check=True, capture_output=True)
    try:
        with tempfile.TemporaryDirectory(prefix="haxepress-install-mysql-") as directory:
            server = SetupServer(Path(directory), "127.0.0.1")
            try:
                client = SetupClient(server.url)
                client.request("/admin/install", inertia=True)
                fields = {
                    "driver": "mysql",
                    "host": "127.0.0.1",
                    "port": str(mysql_port),
                    "database": name,
                    "username": "root",
                    "password": "",
                }
                status, _, result = client.request("/admin/install/database", fields)
                check(
                    status == 200 and result["verified"],
                    "Native MySQL DDL check failed: " + str(status) + " " + str(result),
                )
                password = "MySQL $literal 'quote' # 42!"
                inputs = {
                    "site_name": "MySQL setup",
                    "admin_name": "MySQL Owner",
                    "admin_email": "mysql-owner@example.test",
                    "admin_password": password,
                    "confirm_password": password,
                    "sample_content": "0",
                }
                status, _, result = client.request("/admin/install/finish", inputs)
                check(
                    status == 200 and result["installed"],
                    "MySQL schema/bootstrap failed: " + str(result),
                )
                check(
                    client.request("/admin", inertia=True)[0] == 200,
                    "MySQL administrator dashboard failed",
                )
                config = (server.work / ".env").read_text()
                check(
                    "DB_DRIVER='mysql'" in config and "DB_DATABASE='" + name + "'" in config,
                    "MySQL config was not saved",
                )
                SetupServer.stop(server.process)
                server.start()
                after = SetupClient(server.url)
                after.request("/admin/login")
                check(
                    after.request(
                        "/admin/login", {"email": inputs["admin_email"], "password": password}
                    )[0]
                    == 303,
                    "MySQL setup did not survive restart",
                )
            finally:
                server.close()
    finally:
        subprocess.run(command + ["drop"], cwd=mysql_work, check=True, capture_output=True)
    print(
        "PASS MySQL installation: native DDL validation, complete schema/admin/config initialization, authenticated dashboard and restart/login",
        flush=True,
    )


def verify_trust_rules():
    with tempfile.TemporaryDirectory(prefix="haxepress-install-trust-") as directory:
        work = Path(directory)
        work.chmod(0o700)
        key = base64.b64encode(secrets.token_bytes(32)).decode()
        (work / ".env").write_text("APP_NAME=haxepress_test\nAPP_KEY=" + key + "\n")
        (work / ".env").chmod(0o600)
        classpath = str(TEST_BINARY) + os.pathsep + str(TEST_BINARY.parent / "lib/*")
        result = subprocess.run(
            ["java", "-cp", classpath, "fixtures.InstallationTrustFixture"],
            cwd=work,
            check=True,
            capture_output=True,
            text=True,
        )
        print(result.stdout.strip(), flush=True)


def run():
    verify_trust_rules()
    for configured in (None, "", "192.0.2.11", "deadbeef"):
        with tempfile.TemporaryDirectory(prefix="haxepress-install-loopback-") as name:
            server = SetupServer(Path(name), configured)
            try:
                client = SetupClient(server.url)
                for header in ("Forwarded", "X-Forwarded-For", "X-Real-IP"):
                    value = "for=127.0.0.1" if header == "Forwarded" else "127.0.0.1"
                    status, headers, data = client.request(
                        "/admin/install", headers={header: value}, inertia=True
                    )
                    check(
                        status == 403 and data["props"]["setup"]["blocked"],
                        "A forwarded connection used the loopback exception",
                    )
                    check("set-cookie" not in headers, "A blocked installation started a session")
                check(
                    client.request(
                        "/admin/install/database",
                        {
                            "driver": "sqlite",
                            "file": "bypass.sqlite",
                            "INSTALL_TRUSTED_IPS": "127.0.0.1",
                        },
                        headers={"X-Forwarded-For": "127.0.0.1"},
                    )[0]
                    == 403,
                    "A body/header bypassed installation trust",
                )
                check(
                    not list((server.work / "storage").glob("*.sqlite")),
                    "An untrusted request created a database",
                )
                status, headers, _ = client.request("/")
                check(
                    status == 303 and headers.get("location") == "/admin/install",
                    "Loopback did not automatically redirect to setup",
                )
                status, _, data = client.request("/admin/install", inertia=True)
                check(
                    status == 200
                    and not data["props"]["setup"]["blocked"]
                    and data["props"]["setup"]["message"] == ""
                    and client.csrf,
                    "Loopback setup was blocked by missing, wrong or invalid trusted IP settings",
                )
            finally:
                server.close()
    with tempfile.TemporaryDirectory(prefix="haxepress-install-allowed-") as name:
        server = SetupServer(Path(name), None)
        password = "Setup $literal # 'quote' \\ path 42!"
        try:
            client = SetupClient(server.url)
            check(
                client.request("/admin/install", headers={"X-Forwarded-For": "127.0.0.1"})[0]
                == 403,
                "Forwarded identity headers were accepted",
            )
            status, _, data = client.request("/admin/install", inertia=True)
            check(
                status == 200 and not data["props"]["setup"]["blocked"] and client.csrf,
                "Trusted setup did not open with CSRF",
            )
            html_status, _, html = client.request("/admin/install")
            check(
                html_status == 200
                and "Connect your database" in html
                and "setup-shell" in html
                and "noindex,nofollow" in html,
                "The installation screen did not render through SSR",
            )
            check(
                client.request(
                    "/admin/install/database",
                    {"driver": "sqlite", "file": "setup.sqlite"},
                    csrf=False,
                )[0]
                == 419,
                "Installer database check bypassed CSRF",
            )
            check(
                client.request(
                    "/admin/install/database", {"driver": "sqlite", "file": "../escape.sqlite"}
                )[0]
                == 422,
                "Unsafe SQLite path accepted",
            )
            check(
                client.request(
                    "/admin/install/database",
                    {
                        "driver": "mysql",
                        "host": "127.0.0.1",
                        "port": "1",
                        "database": "setup",
                        "username": "setup",
                        "password": "not-a-live-secret",
                    },
                )[0]
                == 422,
                "Unreachable MySQL connection was reported as verified",
            )
            status, _, database = client.request(
                "/admin/install/database", {"driver": "sqlite", "file": "setup.sqlite"}
            )
            check(status == 200 and database["verified"], "SQLite connection/DDL validation failed")
            check(
                "password" not in json.dumps(database),
                "Database credentials returned to the browser",
            )
            check(
                "APP_INSTALLED=false" in (server.work / ".env").read_text(),
                "Database verification completed setup prematurely",
            )
            inputs = {
                "site_name": "Setup verification",
                "admin_name": "Setup Owner",
                "admin_email": "setup-owner@example.test",
                "admin_password": password,
                "confirm_password": "different",
                "sample_content": "0",
            }
            check(
                client.request("/admin/install/finish", inputs)[0] == 422,
                "Mismatched administrator passwords were accepted",
            )
            inputs["confirm_password"] = password
            status, _, result = client.request("/admin/install/finish", inputs)
            check(
                status == 200 and result["installed"], "First installation failed: " + str(result)
            )
            config = (server.work / ".env").read_text()
            check(
                "APP_INSTALLED='true'" in config
                and "ADMIN_PASSWORD=" in config
                and "UNRELATED_SETTING=preserved" in config,
                "Private configuration was not persisted",
            )
            check(
                stat.S_IMODE((server.work / ".env").stat().st_mode) == 0o600,
                "The installed .env is not private",
            )
            check(
                not list(server.work.glob(".env.install-*")),
                "An installation configuration temporary was left behind",
            )
            check(
                client.request("/admin", inertia=True)[0] == 200,
                "Setup did not authenticate the new administrator",
            )
            check(
                client.request("/admin/install", inertia=True)[0] == 404,
                "The installer reopened after completion",
            )
            with FixtureStore(server.work) as store:
                admin = store.rows(
                    "admins",
                    ["id", "email", "password", "name"],
                    [("email", "=", inputs["admin_email"])],
                    limit=1,
                )[0]
                check(
                    admin["name"] == inputs["admin_name"] and admin["password"] != password,
                    "Administrator password/name was not stored correctly",
                )
                check(
                    store.count("items") == 0,
                    "Optional sample content was inserted without selection",
                )
            SetupServer.stop(server.process)
            server.start()
            after = SetupClient(server.url)
            check(after.request("/admin/install", inertia=True)[0] == 404, "Restart reopened setup")
            check(
                after.request("/admin/login")[0] == 200 and after.csrf,
                "Login did not open after setup restart",
            )
            check(
                after.request(
                    "/admin/login", {"email": inputs["admin_email"], "password": password}
                )[0]
                == 303,
                "Literal password changed after .env reload",
            )
            text = (server.work / "runtime.log").read_text()
            check(
                password not in text and "not-a-live-secret" not in text,
                "Credentials leaked into installer logs",
            )
        finally:
            server.close()
    print(
        "PASS Installation: automatic loopback setup, explicit remote trust, forwarded-header rejection, no blocked sessions/DB writes, native SQLite/DDL and MySQL failure checks, CSRF, admin creation, optional demo data, private atomic dotenv, literal secrets, disabled installer and restart/login",
        flush=True,
    )


if __name__ == "__main__":
    run()
    if os.environ.get("TEST_MYSQL_PORT"):
        verify_mysql(int(os.environ["TEST_MYSQL_PORT"]), Path(os.environ["TEST_MYSQL_WORK"]))
