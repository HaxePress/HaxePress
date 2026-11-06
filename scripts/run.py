#!/usr/bin/env python3
"""Run the JVM application and its loopback-only Inertia React SSR renderer."""

import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def main():
    values = {}
    for line in (ROOT / ".env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            values[key] = value.strip().strip('"')
    renderer = ROOT / "bootstrap/ssr/ssr.js"
    binary = ROOT / "Export/jvm/hxwell.jar"
    if not renderer.exists() or not binary.exists():
        raise SystemExit("Run make build first.")
    ssr = None
    app = None
    try:
        if values.get("INERTIA_SSR_ENABLED", "true") == "true":
            url = urllib.parse.urlsplit(
                values.get("INERTIA_SSR_URL", "http://127.0.0.1:13714/render")
            )
            if url.hostname not in ("127.0.0.1", "localhost"):
                raise SystemExit("The bundled SSR renderer requires a loopback URL.")
            env = os.environ.copy()
            env["INERTIA_SSR_PORT"] = str(url.port or 13714)
            env["CMS_STORAGE_PATH"] = str(
                Path(values.get("STORAGE_PATH", str(ROOT / "storage"))).resolve()
            )
            ssr = subprocess.Popen(["node", str(renderer)], cwd=ROOT, env=env)
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                if ssr.poll() is not None:
                    raise RuntimeError("The Inertia SSR renderer could not start.")
                try:
                    with urllib.request.urlopen(
                        f"http://127.0.0.1:{env['INERTIA_SSR_PORT']}/health", timeout=0.5
                    ) as response:
                        if response.status == 200:
                            break
                except OSError:
                    time.sleep(0.1)
            else:
                raise RuntimeError("The Inertia SSR renderer did not become ready.")
        app = subprocess.Popen(
            ["java", "--enable-native-access=ALL-UNNAMED", "-jar", str(binary), "start"], cwd=ROOT
        )
        return app.wait()
    except KeyboardInterrupt:
        return 130
    finally:
        stop(app)
        stop(ssr)


if __name__ == "__main__":
    sys.exit(main())
