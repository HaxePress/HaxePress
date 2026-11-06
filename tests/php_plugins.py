"""Execute compiled PHP packages through the actual PHP host and native ORM."""

import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from zipfile import ZipFile, ZIP_STORED

from cppia_plugins import archive
from fixture_store import FixtureStore

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_packages import build_plugin, build_php_plugin
from plugin_build import compiler, environment, host_options, host_exports


def run(skip_packages=False):
    php = shutil.which("php")
    if php is None:
        raise SystemExit("PHP CLI with mbstring, OpenSSL and SQLite is required.")
    if not skip_packages:
        subprocess.run([sys.executable, "scripts/build_packages.py"], cwd=ROOT, check=True)
    host = ROOT / "Export/tests/php/host"
    build_plugin(
        ROOT / "tests/plugins/database",
        ROOT / "Export/packages",
        ROOT / "Export/packages/cms-plugin-api-4.info",
    )
    subprocess.run(
        [
            str(compiler()),
            *host_options(),
            "-cp",
            str(ROOT / "tests/haxe"),
            "-main",
            "plugins.PhpHost",
            *host_exports(),
            "-dce",
            "no",
            "--php",
            str(host),
        ],
        cwd=ROOT,
        env=environment(),
        check=True,
    )
    with tempfile.TemporaryDirectory(prefix="cms-php-test-") as name:
        work = Path(name)
        plugin = work / "source"
        shutil.copytree(ROOT / "examples/plugins/reading-companion", plugin)
        source = plugin / "src/example/reading/ReadingPlugin.hx"
        source.write_text(
            source.read_text().replace(
                "var message:String = input.settings.message;",
                "var message:String = 'Updated module: ${input.settings.message}';",
            )
        )
        build_php_plugin(
            plugin, work / "updated", json.loads((plugin / "cms-package.json").read_text())
        )
        invalid = work / "invalid-source/src/invalid/InvalidPlugin.hx"
        invalid.parent.mkdir(parents=True)
        invalid.write_text(
            "package invalid;\n\nclass InvalidPlugin {\n    public function new() {}\n}\n"
        )
        build_php_plugin(
            work / "invalid-source",
            work / "invalid",
            {"server": {"entrypoint": "invalid.InvalidPlugin", "php": "php/module.json"}},
        )
        build_plugin(
            ROOT / "tests/plugins/lifecycle",
            work,
            ROOT / "Export/packages/cms-plugin-api-4.info",
        )
        with ZipFile(ROOT / "Export/packages/reading-companion-2.16.0.zip") as package:
            manifest = json.loads(package.read("cms-package.json"))
            files = {
                path: package.read(path)
                for path in package.namelist()
                if path != "cms-package.json"
            }
        definition = json.loads(files["php/module.json"])
        entry_file = f"php/{next(iter(definition['classes'].values()))}"
        inspection_files = {
            **files,
            entry_file: b'<?php throw new \\RuntimeException("Inspection executed PHP code");',
        }
        (work / "inspection-only.zip").write_bytes(
            archive(manifest, list(inspection_files.items()))
        )
        (work / "streamed.zip").write_bytes(archive(manifest, list(files.items()), descriptor=True))
        legacy = {
            **manifest,
            "server": {key: value for key, value in manifest["server"].items() if key != "php"},
        }
        corrupt = bytearray(archive(manifest, list(files.items()), compression=ZIP_STORED))
        position = corrupt.find(files[entry_file])
        corrupt[position + len(files[entry_file]) - 1] ^= 1
        cases = [
            ("missing-php", archive(legacy, list(files.items()))),
            ("traversal", archive(manifest, [*files.items(), ("../escape.php", "unsafe")])),
            ("checksum", bytes(corrupt)),
            (
                "entry-limit",
                archive(
                    manifest,
                    [*files.items(), *[(f"extra/{str(index)}", "") for index in range(256)]],
                ),
            ),
        ]
        for label, data in cases:
            (work / (f"{label}.zip")).write_bytes(data)
        values = {
            "APP_NAME": "haxepress_test",
            "APP_ENV": "development",
            "APP_KEY": base64.b64encode(os.urandom(32)).decode(),
            "DB_DRIVER": "sqlite",
            "DB_PATH": str(work / "storage/cms.sqlite"),
            "CACHE_PATH": str(work / "storage/cache"),
            "APP_URL": "http://localhost",
            "SESSION_PATH": str(work / "storage/sessions"),
        }
        (work / "storage/cache").mkdir(parents=True)
        (work / ".env").write_text("".join(f"{key}={value}\n" for key, value in values.items()))
        with FixtureStore(work) as fixtures:
            fixtures.call("initialize_schema")
            fixtures.create(
                "settings",
                [
                    {"key": "site_name", "value": "PHP test"},
                    {"key": "locale", "value": "tr"},
                ],
            )
            fixtures.create(
                "items",
                [
                    {
                        "title": "PHP feed content item",
                        "slug": "php-feed",
                        "excerpt": "A PHP plugin feed.",
                        "content": "Private body",
                        "category": "",
                        "status": "published",
                        "published_at": "2026-11-04",
                        "created_at": "2026-11-04",
                        "updated_at": "2026-11-04",
                    }
                ],
            )
        subprocess.run(
            [php, str(host / "index.php"), str(ROOT / "Export/packages")],
            cwd=work,
            check=True,
            env=environment(),
            timeout=90,
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-packages", action="store_true")
    arguments = parser.parse_args()
    run(arguments.skip_packages)
