"""Fresh installs require a trusted socket peer and write private, literal configuration."""

import base64
import html
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
import re
import tempfile
import time
import urllib.parse

from e2e import check
from fixture_store import FixtureStore, TEST_BINARY

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = Path(os.environ.get("CMS_TEST_PUBLIC_PATH", ROOT / "public"))
PACKAGES = Path(os.environ.get("CMS_TEST_PACKAGES_PATH", ROOT / "private/packages"))
sys.path.insert(0, str(ROOT / "scripts"))
from setup import prepare_environment


def port():
    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0))
        return reserved.getsockname()[1]


class SetupClient:
    def __init__(self, address):
        self.address = urllib.parse.urlsplit(address)
        self.cookies = {}
        self.csrf = ""

    def request(
        self, path, values=None, headers=None, csrf=True, data=False, raw=None, binary=False
    ):
        fields = {"Accept": "application/json"}
        if self.cookies:
            fields["Cookie"] = "; ".join(f"{key}={value}" for key, value in self.cookies.items())
        if data:
            fields["X-Well-Data"] = "true"
        body = None
        if values is not None or raw is not None:
            body = raw if raw is not None else json.dumps(values)
            fields["Content-Type"] = (
                "application/octet-stream" if raw is not None else "application/json"
            )
            if csrf:
                fields["X-CSRF-TOKEN"] = self.csrf
        fields.update(headers or {})
        connection = http.client.HTTPConnection(
            self.address.hostname, self.address.port, timeout=35
        )
        try:
            connection.request("GET" if body is None else "POST", path, body, fields)
            response = connection.getresponse()
            payload = response.read()
            for key, value in response.getheaders():
                if key.lower() == "set-cookie":
                    parsed = http.cookies.SimpleCookie()
                    parsed.load(value)
                    for name, item in parsed.items():
                        self.cookies[name] = item.value
            normalized = {key.lower(): value for key, value in response.getheaders()}
            if binary:
                return response.status, normalized, payload
            payload = payload.decode()
            if "application/json" in normalized.get("content-type", ""):
                result = json.loads(payload) if payload else {}
                if normalized.get("x-well-data") == "true" and result["props"].get("csrfToken"):
                    self.csrf = result["props"]["csrfToken"]
            else:
                result = payload
                token = re.search(r'name="_token" value="([^"]+)"', payload)
                if token:
                    self.csrf = html.unescape(token.group(1))
            return response.status, normalized, result
        finally:
            connection.close()


class SetupServer:
    def __init__(self, work, trusted, *, app_key=None):
        self.work = work
        self.port = port()
        self.url = f"http://127.0.0.1:{str(self.port)}"
        work.chmod(0o700)
        (work / "storage").mkdir()
        (work / "public").symlink_to(PUBLIC, target_is_directory=True)
        (work / "private").mkdir()
        (work / "private/packages").symlink_to(PACKAGES, target_is_directory=True)
        (work / "private/seeds").symlink_to(ROOT / "private/seeds", target_is_directory=True)
        prepare_environment(work)
        initial_key_line = next(
            line for line in (work / ".env").read_text().splitlines() if line.startswith("APP_KEY=")
        )
        if app_key is not None:
            initial_key_line = f"APP_KEY={app_key}"
        self.application_key_line = initial_key_line
        values = {
            "APP_NAME": "haxepress_test",
            "APP_ENV": "development",
            "APP_INSTALLED": "false",
            "APP_KEY": initial_key_line.split("=", 1)[1],
            "APP_URL": self.url,
            "HOST": "127.0.0.1",
            "PORT": str(self.port),
            "DB_DRIVER": "sqlite",
            "DB_PATH": str(work / "storage/untouched.sqlite"),
            "STORAGE_PATH": str(work / "storage"),
            "DATA_PATH": str(work / "data"),
            "CACHE_PATH": str(work / "storage/cache"),
            "SESSION_PATH": str(work / "storage/sessions"),
            "WELL_DATA_RESPONSES": "1",
            "UNRELATED_SETTING": "preserved",
        }
        if trusted is not None:
            values["INSTALL_TRUSTED_IPS"] = trusted
        (work / ".env").write_text("".join(f"{key}={value}\n" for key, value in values.items()))
        (work / ".env").chmod(0o600)
        self.log = (work / "runtime.log").open("w+")
        self.process = None
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
                status, _, _ = client.request("/admin/install", data=True)
                if status in (200, 403, 404):
                    return
            except (OSError, http.client.HTTPException):
                pass
            time.sleep(0.1)
        self.log.flush()
        raise RuntimeError(
            f"Installer did not start: {(self.work / 'runtime.log').read_text()[-3000:]}"
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
        self.log.close()
        if sys.exc_info()[0] is not None:
            failure = ROOT / "outputs/installer/failure" / self.work.name
            failure.mkdir(parents=True, exist_ok=True)
            failure.chmod(0o700)
            shutil.copytree(self.work, failure, dirs_exist_ok=True, symlinks=True)


def verify_mysql(mysql_port, mysql_work):
    name = f"haxepress_install_{secrets.token_hex(5)}"
    classpath = f"{str(TEST_BINARY)}{os.pathsep}{str(TEST_BINARY.parent / 'lib/*')}"
    command = ["java", "-cp", classpath, "fixtures.MysqlSetupFixture", str(mysql_port), name]
    subprocess.run(command, cwd=mysql_work, check=True, capture_output=True)
    try:
        with tempfile.TemporaryDirectory(prefix="haxepress-install-mysql-") as directory:
            server = SetupServer(Path(directory), "127.0.0.1")
            try:
                client = SetupClient(server.url)
                client.request("/admin/install", data=True)
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
                    f"Native MySQL DDL check failed: {str(status)} {str(result)}",
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
                    f"MySQL schema/bootstrap failed: {str(result)}",
                )
                check(
                    client.request("/admin", data=True)[0] == 200,
                    "MySQL administrator dashboard failed",
                )
                config = (server.work / ".env").read_text()
                check(
                    "DB_DRIVER='mysql'" in config and f"DB_DATABASE='{name}'" in config,
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
        (work / ".env").write_text(f"APP_NAME=haxepress_test\nAPP_KEY={key}\n")
        (work / ".env").chmod(0o600)
        classpath = f"{str(TEST_BINARY)}{os.pathsep}{str(TEST_BINARY.parent / 'lib/*')}"
        result = subprocess.run(
            ["java", "-cp", classpath, "fixtures.InstallationTrustFixture"],
            cwd=work,
            check=True,
            capture_output=True,
            text=True,
        )
        print(result.stdout.strip(), flush=True)


def verify_environment_bootstrap():
    with tempfile.TemporaryDirectory(prefix="haxepress-native-environment-") as directory:
        work = Path(directory)
        work.chmod(0o700)
        fresh = work / "fresh"
        fresh.mkdir()
        check(prepare_environment(fresh), "A fresh environment was not prepared")
        source = (fresh / ".env").read_text()
        key = next(
            line.split("=", 1)[1] for line in source.splitlines() if line.startswith("APP_KEY=")
        )
        check(
            len(base64.b64decode(key, validate=True)) == 32, "The native application key is invalid"
        )
        check(
            stat.S_IMODE((fresh / ".env").stat().st_mode) == 0o600, "Bootstrap .env is not private"
        )
        check(not prepare_environment(fresh), "Repeated setup recreated the environment")
        check(
            (fresh / ".env").read_text() == source,
            "Repeated setup changed the application key/configuration",
        )

        native = work / "native"
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/hxwell.py"), "new", os.path.relpath(native, ROOT)],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        check(
            result.returncode == 0 and (native / ".env").exists(),
            "HxWell did not create the native project environment",
        )
        check(not prepare_environment(native), "An existing native environment was replaced")
        native_source = (native / ".env").read_text()
        native_key = next(
            line for line in native_source.splitlines() if line.startswith("APP_KEY=")
        )
        check(
            native_key != "APP_KEY=" and native_key != f"APP_KEY={key}",
            "Native project bootstrap reused an application key",
        )
        (native / ".env").write_text(
            f"{native_source}APP_INSTALLED=true\n# Keep the framework environment\n"
        )
        preserved = (native / ".env").read_bytes()
        prepare_environment(native)
        check(
            (native / ".env").read_bytes() == preserved,
            "Existing framework settings/key were overwritten",
        )
        check(
            not list(work.rglob(".env.setup-*")), "Bootstrap left a private environment temporary"
        )
    print(
        "PASS Native environment: HxWell project/key generation, private files, existing-key preservation and idempotent setup",
        flush=True,
    )


def run():
    verify_environment_bootstrap()
    verify_trust_rules()
    for configured in (None, "", "192.0.2.11", "deadbeef"):
        with tempfile.TemporaryDirectory(prefix="haxepress-install-loopback-") as name:
            server = SetupServer(Path(name), configured)
            try:
                client = SetupClient(server.url)
                for header in ("Forwarded", "X-Forwarded-For", "X-Real-IP"):
                    value = "for=127.0.0.1" if header == "Forwarded" else "127.0.0.1"
                    status, headers, data = client.request(
                        "/admin/install", headers={header: value}, data=True
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
                    not list((server.work / "storage").glob("*.sqlite"))
                    and not list((server.work / "data").glob("*.sqlite")),
                    "An untrusted request created a database",
                )
                status, headers, _ = client.request("/")
                check(
                    status == 303 and headers.get("location") == "/admin/install",
                    "Loopback did not automatically redirect to setup",
                )
                status, _, data = client.request("/admin/install", data=True)
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
            status, _, data = client.request("/admin/install", data=True)
            check(
                status == 200 and not data["props"]["setup"]["blocked"] and client.csrf,
                "Trusted setup did not open with CSRF",
            )
            html_status, html_headers, page = client.request("/admin/install")
            check(
                html_status == 200
                and "Connect your database" in page
                and "setup-shell" in page
                and "noindex,nofollow" in page
                and "data-page=" not in page
                and 'name="_token"' in page
                and html_headers.get("cache-control") == "private, no-store",
                "The installation screen did not render as server HTML",
            )
            fragment_status, fragment_headers, fragment = client.request(
                "/admin/install", headers={"Well-Fragment": "setup"}
            )
            check(
                fragment_status == 200
                and fragment_headers.get("well-fragment") == "setup"
                and fragment.startswith('<section class="setup-content"')
                and "Connect your database" in fragment
                and "<html" not in fragment,
                "The installation fragment request did not return only the setup section",
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
            # `$` also matches before a final line break, which would name a file or driver.
            for ending in ["\n", "\r\n", "\u2028"]:
                for fields in [
                    {"driver": "sqlite", "file": f"setup.sqlite{ending}"},
                    {"driver": f"sqlite{ending}", "file": "setup.sqlite"},
                ]:
                    check(
                        client.request("/admin/install/database", fields)[0] == 422,
                        f"A database setting ending in {ending!r} was accepted",
                    )
            data = server.work / "data"
            names = [entry.name for entry in data.iterdir()] if data.exists() else []
            check(
                all(name.isprintable() for name in names),
                "A database file was named with a line break",
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
            # Ports are 1-65535 in plain digits; anything else fails validation before a connection.
            for port in ["0", "65536", "99999", "3306a", "+3306", " 3306", "-1", "", "123456"]:
                status, _, rejected = client.request(
                    "/admin/install/database",
                    {
                        "driver": "mysql",
                        "host": "127.0.0.1",
                        "port": port,
                        "database": "setup",
                        "username": "setup",
                    },
                )
                check(
                    status == 422 and "Check the database fields" in rejected["error"],
                    f"The database port {port!r} was not rejected by validation: {rejected}",
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
                "APP_KEY": "must-not-replace-the-framework-key",
            }
            check(
                client.request("/admin/install/finish", inputs)[0] == 422,
                "Mismatched administrator passwords were accepted",
            )
            for ending in ["\n", "\r\n"]:
                line_email = {
                    **inputs,
                    "admin_email": f"{inputs['admin_email']}{ending}",
                    "confirm_password": password,
                }
                line_password = {
                    **inputs,
                    "admin_password": f"{password}{ending}",
                    "confirm_password": f"{password}{ending}",
                }
                for changed in [line_email, line_password]:
                    check(
                        client.request("/admin/install/finish", changed)[0] == 422,
                        f"An administrator email or password ending in {ending!r} was accepted",
                    )
            inputs["confirm_password"] = password
            environment = server.work / ".env"
            original_environment = environment.read_bytes()
            environment.unlink()
            check(
                client.request("/admin/install/finish", inputs)[0] == 422,
                "Installation completed without the framework environment",
            )
            check(
                not environment.exists(),
                "The web installer recreated a missing framework environment",
            )
            environment.write_bytes(original_environment)
            environment.chmod(0o600)
            status, _, result = client.request("/admin/install/finish", inputs)
            check(
                status == 200 and result["installed"], f"First installation failed: {str(result)}"
            )
            config = (server.work / ".env").read_text()
            check(
                "APP_INSTALLED='true'" in config and "UNRELATED_SETTING=preserved" in config,
                "Private configuration was not persisted",
            )
            check(
                password not in config and inputs["admin_email"] not in config,
                "The installer kept administrator credentials in .env",
            )
            check(
                (server.work / "data/setup.sqlite").is_file()
                and str(server.work / "data/setup.sqlite") in config
                and not list((server.work / "storage").rglob("*.sqlite")),
                "The installer did not keep the database in the data folder, apart from storage",
            )
            check(
                server.application_key_line in config.splitlines(),
                "The installer changed HxWell's application key",
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
                client.request("/admin", data=True)[0] == 200,
                "Setup did not authenticate the new administrator",
            )
            for path, values in (
                ("/admin/install", None),
                ("/admin/install/database", {}),
                ("/admin/install/finish", {}),
            ):
                status, headers, page = client.request(path, values, csrf=False, data=True)
                check(
                    status == 404
                    and isinstance(page, dict)
                    and page.get("component") == "NotFound"
                    and "set-cookie" not in headers,
                    f"{path} did not reach the site 404 before session and CSRF middleware",
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
            check(after.request("/admin/install", data=True)[0] == 404, "Restart reopened setup")
            check(
                after.request("/admin/login")[0] == 200 and after.csrf,
                "Login did not open after setup restart",
            )
            check(
                after.request(
                    "/admin/login", {"email": inputs["admin_email"], "password": password}
                )[0]
                == 303,
                "The administrator could not sign in after a restart",
            )
            # Earlier installers left the first administrator in .env; startup clears it.
            SetupServer.stop(server.process)
            environment = server.work / ".env"
            legacy = [
                line
                for line in environment.read_text().splitlines()
                if not line.startswith(("ADMIN_NAME=", "ADMIN_EMAIL=", "ADMIN_PASSWORD="))
            ]
            legacy += [
                "ADMIN_NAME='Setup Owner'",
                f"ADMIN_EMAIL='{inputs['admin_email']}'",
                "ADMIN_PASSWORD='" + password.replace("\\", "\\\\").replace("'", "\\'") + "'",
            ]
            environment.write_text("\n".join(legacy) + "\n")
            environment.chmod(0o600)
            server.start()
            config = environment.read_text()
            check(
                password not in config
                and inputs["admin_email"] not in config
                and "ADMIN_PASSWORD=''" in config
                and "UNRELATED_SETTING=preserved" in config,
                "Startup kept administrator credentials from an earlier installer in .env",
            )
            check(
                stat.S_IMODE(environment.stat().st_mode) == 0o600,
                "Clearing administrator credentials made .env readable",
            )
            cleared = SetupClient(server.url)
            cleared.request("/admin/login")
            check(
                cleared.request(
                    "/admin/login", {"email": inputs["admin_email"], "password": password}
                )[0]
                == 303,
                "The administrator could not sign in after .env was cleared",
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
