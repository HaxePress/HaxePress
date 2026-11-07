#!/usr/bin/env python3
"""Package a built HaxePress for a GitHub release.

Run `make build` first, then `python3 scripts/release.py <tag> <output folder>`.
The output holds the application built for the JVM and for PHP, one archive
each. The plugins and themes of this build are inside both archives, in
`public/packages`, and are not released as files of their own.
"""

import argparse
import json
from pathlib import Path
import re
import shutil
import stat
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
APPLICATION = ROOT / "Export/jvm"
PHP_APPLICATION = ROOT / "Export/php"
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

SETUP_PHP = """<?php
// Creates .env from .env.example with a new random APP_KEY. Run once: php setup.php
if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}
chdir(__DIR__);
if (file_exists('.env')) {
    echo ".env already exists and was kept.\\n";
    exit(0);
}
$key = base64_encode(random_bytes(32));
$settings = preg_replace('/^APP_KEY=.*$/m', 'APP_KEY=' . $key, file_get_contents('.env.example'));
umask(077);
file_put_contents('.env', $settings);
chmod('.env', 0600);
echo "Created .env with a new APP_KEY. Keep it private.\\n";
"""

# Vite names built files after their content, so Apache may let browsers keep them for a year.
BUILT_ASSET_CACHE = """
<IfModule mod_headers.c>
    <If "%{REQUEST_URI} =~ m#^/build/assets/#">
        Header set Cache-Control "public, max-age=31536000, immutable"
    </If>
</IfModule>
"""

PHP_README = """# HaxePress {version} for PHP

HaxePress {cms} (plugin API {api}) built for PHP with HxWell's PHP driver.

## Requirements

- PHP 8.1 or later with the `mbstring` and `sqlite3` extensions (`mysqli`
  for MySQL), and opcache for speed.
- A web server whose document root is the `public/` folder and which sends
  every request that is not a file to `public/index.php`. Apache uses the
  included `.htaccess`. Keep the other folders outside the document root.

## Install

1. Unpack this archive and run `php setup.php` in its folder. It creates
   `.env` from `.env.example` with a new `APP_KEY`; keep that file private.
2. Make `data/` and `storage/` (both created on first use) and `.env` writable
   by PHP.
3. The installer accepts direct connections from 127.0.0.1 only. On a
   remote server, add your IP address to `INSTALL_TRUSTED_IPS` in `.env`.
4. Open `/admin/install` on your site and follow the installer.
5. Run due scheduled tasks, such as scheduled publishing, every minute:
   `* * * * * cd /path/to/haxepress && php hxwell.boot.php schedule:run`.
   Without cron they also run after page requests.

The database lives in `data/` and uploaded files in `storage/`. Keep `.env`,
`data/` and `storage/` when you upgrade; replace everything else. Compiled
templates are kept in `storage/cache/views` as PHP files.

## AI connections (MCP)

The site serves MCP itself at the `/mcp/sessions/...` links that **Connect AI**
generates; no other program is needed. The PHP build has no WebSockets, so
the admin pages and the theme editor send their MCP messages over HTTP and
check for changes every few seconds instead of receiving them live. The
`preview_theme_design` tool, which looks at a theme in headless Chrome,
needs the JVM build.

## Plugins and themes

The plugins and themes of this release are inside this archive, in
`public/packages`. Install them from Plugins and Themes in the
administration panel; each plugin contains its JVM, CPPIA and PHP builds.
"""

README = """# HaxePress {version}

HaxePress {cms} (plugin API {api}) built for the JVM.

## Requirements

- Java 21 or later. The site serves its pages and its MCP server (AI
  connections) itself.
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

The database lives in `data/` and uploaded files in `storage/`; the site
creates both. Keep `.env`, `data/` and `storage/` when you upgrade; replace
everything else.

## Plugins and themes

The plugins and themes of this release are inside this archive, in
`public/packages`. Install them from Plugins and Themes in the
administration panel; each plugin contains its JVM, CPPIA and PHP builds.
"""


def release_version(tag):
    match = TAG.match(tag)
    if not match:
        raise SystemExit(f"Use a release tag such as 1.2.3 or v1.2.3, not {tag}.")
    return match.group(1)


def packages(cms):
    """The packages this build produced, by their manifests' versions; the archives carry them."""
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


def php_application(version, cms, current, output):
    boot = PHP_APPLICATION / "hxwell.boot.php"
    if not boot.is_file():
        raise SystemExit("Run make build first; Export/php/hxwell.boot.php is missing.")
    folder = f"haxepress-{version}"
    target = output / f"{folder}-php.zip"
    shipped = set(current)
    with ZipFile(target, "w") as archive:
        add_file(archive, boot, f"{folder}/hxwell.boot.php")
        add_tree(archive, PHP_APPLICATION / "lib", f"{folder}/lib")
        add_tree(archive, PHP_APPLICATION / "res", f"{folder}/res")
        # The same site assets as the JVM build, served through PHP's front controller.
        add_tree(
            archive,
            APPLICATION / "public",
            f"{folder}/public",
            keep=lambda path: path.parent.name != "packages" or path.name in shipped,
        )
        add_file(archive, PHP_APPLICATION / "public/index.php", f"{folder}/public/index.php")
        rewrites = (PHP_APPLICATION / "public/.htaccess").read_text()
        add_text(archive, f"{rewrites.rstrip()}\n{BUILT_ASSET_CACHE}", f"{folder}/public/.htaccess")
        add_tree(archive, ROOT / "database", f"{folder}/database")
        add_file(archive, ROOT / "cms.json", f"{folder}/cms.json")
        add_file(archive, ROOT / ".env.example", f"{folder}/.env.example")
        add_text(archive, SETUP_PHP, f"{folder}/setup.php")
        readme = PHP_README.format(version=version, cms=cms["version"], api=cms["pluginApiVersion"])
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
    files = [
        application(version, cms, current, output),
        php_application(version, cms, current, output),
    ]
    for path in sorted(files):
        print(f"{path.stat().st_size:>12,}  {path.name}")


if __name__ == "__main__":
    main()
