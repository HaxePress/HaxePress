#!/usr/bin/env python3
"""Package a built HaxePress for a GitHub release.

Run `make build` first, then `python3 scripts/release.py <tag> <output folder>`.
The output holds the JVM application as one archive, the extension packages
of this build (each plugin carries its JVM, CPPIA and PHP builds) and a
SHA256SUMS.txt file. The application itself runs on the JVM only: its HTTP
server needs a threaded target, so there is no PHP build of the application.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import stat
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
APPLICATION = ROOT / "Export/jvm"
TAG = re.compile(r"^v?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)$")

START = """#!/bin/sh
# Starts HaxePress from this folder. On the first run it creates .env from
# .env.example with a new random APP_KEY; keep that file private.
set -eu
cd "$(dirname "$0")"
if [ ! -f .env ]; then
  key=$(openssl rand -base64 32 2>/dev/null \\
    || python3 -c 'import base64, os; print(base64.b64encode(os.urandom(32)).decode())')
  umask 077
  sed "s|^APP_KEY=.*|APP_KEY=$key|" .env.example > .env
  echo "Created .env with a new APP_KEY."
  echo "Open http://127.0.0.1:3000/admin/install on this computer to install HaxePress."
fi
exec java --enable-native-access=ALL-UNNAMED -jar hxwell.jar start
"""

README = """# HaxePress {version}

HaxePress {cms} (plugin API {api}) built for the JVM.

## Requirements

- Java 21 or later.
- Node.js 22 or later, for the site's MCP server (AI connections). Without
  it the site runs and MCP stays unavailable.
- Chrome or Chromium, only for the MCP theme preview tool.

## Install

1. Unpack this archive and open its folder.
2. Run `./start.sh`. The first run creates `.env` from `.env.example` with a
   new `APP_KEY`; later runs keep it. To set things up yourself instead, copy
   `.env.example` to `.env`, set `APP_KEY` to 32 random bytes in Base64
   (`openssl rand -base64 32`) and run
   `java --enable-native-access=ALL-UNNAMED -jar hxwell.jar start`.
3. Open http://127.0.0.1:3000/admin/install on the same computer and follow
   the installer. Other addresses need `INSTALL_TRUSTED_IPS` in `.env`.

Site data lives in `storage/`, which the site creates. Keep `.env` and
`storage/` when you upgrade; replace everything else.

## Extension packages

The `.zip` packages published next to this archive install through Themes and
Plugins in the administration panel. Each plugin package contains its JVM,
CPPIA and PHP builds. `cms-plugin-api-{api}.jar` and `.zip` are the plugin SDK.
"""


def release_version(tag):
    match = TAG.match(tag)
    if not match:
        raise SystemExit(f"Use a release tag such as 1.2.3 or v1.2.3, not {tag}.")
    return match.group(1)


def packages(cms):
    """The extension packages this build produced, by their manifests' versions."""
    names = [f"cms-plugin-api-{cms['pluginApiVersion']}.{kind}" for kind in ("jar", "zip")]
    for plugin in sorted((ROOT / "examples/plugins").iterdir()):
        manifest = plugin / "cms-package.json"
        if manifest.is_file():
            data = json.loads(manifest.read_text())
            names.append(f"{data['slug']}-{data['version']}.zip")
    for source in sorted((ROOT / "examples/themes").iterdir()):
        manifest = ROOT / "Export/themes" / source.name / "cms-package.json"
        if source.is_dir() and manifest.is_file():
            names.append(f"{source.name}-{json.loads(manifest.read_text())['version']}.zip")
    missing = [name for name in names if not (ROOT / "Export/packages" / name).is_file()]
    if missing:
        raise SystemExit(f"Run make build first; these packages are missing: {missing}")
    return names


def add_file(archive, source, name, executable=False):
    info = ZipInfo.from_file(source, name)
    info.compress_type = ZIP_DEFLATED
    mode = 0o755 if executable else 0o644
    info.external_attr = (stat.S_IFREG | mode) << 16
    with open(source, "rb") as stream:
        archive.writestr(info, stream.read())


def add_text(archive, text, name, executable=False):
    info = ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
    info.compress_type = ZIP_DEFLATED
    mode = 0o755 if executable else 0o644
    info.external_attr = (stat.S_IFREG | mode) << 16
    archive.writestr(info, text)


def add_tree(archive, source, name, keep=lambda path: True):
    # Folders such as build/.vite hold files the site reads; only drop system clutter and secrets.
    for path in sorted(source.rglob("*")):
        relative = path.relative_to(source)
        junk = path.name in (".DS_Store", ".env") or path.name.startswith("._")
        if path.is_file() and not junk and keep(path):
            add_file(archive, path, f"{name}/{relative.as_posix()}")


def application(version, cms, current, output):
    jar = APPLICATION / "hxwell.jar"
    if not jar.is_file():
        raise SystemExit("Run make build first; Export/jvm/hxwell.jar is missing.")
    folder = f"haxepress-{version}"
    target = output / f"{folder}-jvm.zip"
    shipped = set(current)
    with ZipFile(target, "w") as archive:
        add_file(archive, jar, f"{folder}/hxwell.jar")
        add_tree(archive, APPLICATION / "lib", f"{folder}/lib")
        # Only this build's packages: the bundled plugins install from public/packages.
        add_tree(
            archive,
            APPLICATION / "public",
            f"{folder}/public",
            keep=lambda path: path.parent.name != "packages" or path.name in shipped,
        )
        add_tree(archive, ROOT / "database", f"{folder}/database")
        add_file(archive, ROOT / "cms.json", f"{folder}/cms.json")
        add_file(archive, ROOT / ".env.example", f"{folder}/.env.example")
        add_text(archive, START, f"{folder}/start.sh", executable=True)
        readme = README.format(version=version, cms=cms["version"], api=cms["pluginApiVersion"])
        add_text(archive, readme, f"{folder}/README.md")
        names = archive.namelist()
    if any(name.endswith("/.env") for name in names):
        raise SystemExit("The application archive must not contain an .env file.")
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("tag", help="the release tag, such as 0.0.1 or v0.0.1")
    parser.add_argument("output", type=Path, help="the folder to write the release files to")
    arguments = parser.parse_args()
    version = release_version(arguments.tag)
    cms = json.loads((ROOT / "cms.json").read_text())
    current = packages(cms)
    output = arguments.output
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    files = [application(version, cms, current, output)]
    for name in current:
        files.append(Path(shutil.copy2(ROOT / "Export/packages" / name, output / name)))
    sums = []
    for path in sorted(files):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        sums.append(f"{digest}  {path.name}")
    (output / "SHA256SUMS.txt").write_text("\n".join(sums) + "\n")
    for path in sorted(files):
        print(f"{path.stat().st_size:>12,}  {path.name}")


if __name__ == "__main__":
    main()
