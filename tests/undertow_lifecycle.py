"""Compile and run the real Undertow WebSocket adapter independently of Crossbyte.

Requires Maven and a JDK. Dependencies are isolated under .tools; they are not
added to the application's JVM runtime or production dependency lock.
"""

import base64
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile
import time

from websocket_lifecycle import request, run

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from plugin_build import compiler, environment, host_options


def main():
    dependencies = ROOT / ".tools/undertow-lifecycle/lib"
    dependencies.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "mvn",
            "-q",
            "-f",
            str(ROOT / "tests/undertow-pom.xml"),
            "-Dmaven.repo.local=" + str(ROOT / ".tools/maven-cache"),
            "dependency:copy-dependencies",
            "-DincludeScope=runtime",
            "-DoutputDirectory=" + str(dependencies),
        ],
        cwd=ROOT,
        check=True,
    )
    binary = ROOT / "Export/tests/undertow/hxwell.jar"
    command = [
        str(compiler()),
        *host_options(),
        "-lib",
        "hxjava",
        "-cp",
        "tests/haxe",
        "-main",
        "fixtures.UndertowLifecycleServer",
        "--jvm",
        str(binary),
    ]
    for directory in (ROOT / "java-lib", dependencies):
        for library in sorted(directory.glob("*.jar")):
            command.extend(["-java-lib", str(library)])
    subprocess.run(command, cwd=ROOT, env=environment(), check=True)
    with tempfile.TemporaryDirectory(prefix="undertow-session-audit-") as name:
        work = Path(name)
        work.chmod(0o700)
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        values = {
            "APP_KEY": base64.b64encode(secrets.token_bytes(32)).decode(),
            "APP_NAME": "haxepress_test",
            "PORT": str(port),
        }
        (work / ".env").write_text(
            "".join(key + "=" + value + "\n" for key, value in values.items())
        )
        (work / ".env").chmod(0o600)
        with (work / "server.log").open("w+") as log:
            server = subprocess.Popen(
                ["java", "-jar", str(binary)], cwd=work, stdout=log, stderr=subprocess.STDOUT
            )
            base = "http://127.0.0.1:" + str(port)
            try:
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    if server.poll() is not None:
                        raise RuntimeError("Undertow probe exited before startup")
                    try:
                        request(base, "/__fixtures/ws/status")
                        break
                    except OSError:
                        time.sleep(0.1)
                else:
                    raise RuntimeError("Undertow probe did not start")
                print("Undertow: " + json.dumps(run(base, blocked=False)), flush=True)
            except Exception:
                log.flush()
                log.seek(0)
                print(log.read()[-4000:], file=sys.stderr)
                raise
            finally:
                if server.poll() is None:
                    server.terminate()
                    try:
                        server.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        server.kill()
                        server.wait()


if __name__ == "__main__":
    main()
