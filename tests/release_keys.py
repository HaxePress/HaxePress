#!/usr/bin/env python3
"""Checks that every installation of a release gets its own APP_KEY.

Run `make build` first. The check packages the JVM and PHP applications
like a release and installs each archive twice: `start.sh` (without
starting Java) and `setup.php` must each create a private .env with a new
random 32-byte key, keep that key when they run again, and no archive may
contain the key of this checkout. Keys are compared, never printed.
"""

import base64
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import release  # noqa: E402


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"PASS {message}")


def app_key(folder):
    for line in (folder / ".env").read_text().splitlines():
        if line.startswith("APP_KEY="):
            return line.split("=", 1)[1].strip()
    return ""


def unpack(archive, target):
    with zipfile.ZipFile(archive) as files:
        files.extractall(target)
    return next(target.glob("haxepress-*"))


def install_jvm(folder):
    # start.sh creates .env and then starts Java; stop where Java would start.
    script = (
        (folder / "start.sh")
        .read_text()
        .replace("exec java --enable-native-access=ALL-UNNAMED -jar hxwell.jar start", "exit 0")
    )
    subprocess.run(["sh", "-c", script], cwd=folder, check=True, capture_output=True)


def install_php(folder):
    subprocess.run(["php", "setup.php"], cwd=folder, check=True, capture_output=True)


def contains(folder, secret):
    """Whether any file in `folder`, or in a JAR inside it, contains `secret`."""
    needle = secret.encode()
    for path in folder.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix == ".jar":
            with zipfile.ZipFile(path) as jar:
                if any(needle in jar.read(name) for name in jar.namelist()):
                    return True
        elif needle in path.read_bytes():
            return True
    return False


def main():
    development = app_key(ROOT) if (ROOT / ".env").is_file() else ""
    cms = json.loads((ROOT / "cms.json").read_text())
    current = release.packages(cms)
    with tempfile.TemporaryDirectory(prefix="haxepress-keys-") as name:
        work = Path(name)
        archives = {
            "JVM": (release.application("0.0.0", cms, current, work), install_jvm),
            "PHP": (release.php_application("0.0.0", cms, current, work), install_php),
        }
        keys = []
        for target, (archive, install) in archives.items():
            for copy in (1, 2):
                folder = unpack(archive, work / f"{target}-{copy}")
                check(
                    not (folder / ".env").exists(), f"{target} install {copy} starts without .env"
                )
                if copy == 1 and development:
                    check(
                        not contains(folder, development),
                        f"the {target} archive does not contain this checkout's APP_KEY",
                    )
                install(folder)
                key = app_key(folder)
                check(
                    len(base64.b64decode(key, validate=True)) == 32,
                    f"{target} key {copy} is 32 bytes",
                )
                mode = stat.S_IMODE(os.stat(folder / ".env").st_mode)
                check(mode == 0o600, f"{target} .env {copy} is private")
                install(folder)
                check(
                    app_key(folder) == key, f"{target} install {copy} keeps its key when run again"
                )
                keys.append(key)
        check(len(set(keys)) == len(keys), "every installation has its own key")
        check(development not in keys, "no installation reuses this checkout's key")
    print("Release key checks passed.")


if __name__ == "__main__":
    main()
