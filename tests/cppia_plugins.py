"""Compile a native C++ host and run real CPPIA package/ABI/update checks."""

import base64
import argparse
import io
import json
import os
from pathlib import Path
import platform
import struct
import shutil
import subprocess
import sys
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED, ZIP_STORED
from fixture_store import FixtureStore

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from plugin_build import host_options, external_host_options, host_exports
from build_packages import build_plugin

ROOT = Path(__file__).resolve().parents[1]


def archive(manifest, files, compression=ZIP_DEFLATED, descriptor=False):
    class StreamingBuffer(io.BytesIO):
        def seek(self, *_):
            raise io.UnsupportedOperation("streaming output")

    output = StreamingBuffer() if descriptor else io.BytesIO()
    with ZipFile(output, "w", compression=compression) as package:
        package.writestr("cms-package.json", json.dumps(manifest))
        for name, data in files:
            package.writestr(name, data)
    return output.getvalue()


def run(skip_packages=False):
    compiler = Path(os.environ.get("HXWELL_HAXE", ROOT / ".tools/haxe/haxe")).resolve()
    environment = {
        **os.environ,
        "PATH": str(compiler.parent) + os.pathsep + os.environ["PATH"],
        "HAXE_STD_PATH": str(ROOT / ".tools/haxe/std"),
    }
    if platform.system() == "Darwin":
        environment.setdefault("MACOSX_DEPLOYMENT_TARGET", "11.0")
    if not skip_packages:
        subprocess.run(
            [sys.executable, str(ROOT / "scripts/build_packages.py")],
            cwd=ROOT,
            check=True,
            env=environment,
        )
    output = ROOT / "Export/tests/cppia"
    build_plugin(
        ROOT / "tests/plugins/database",
        ROOT / "Export/packages",
        ROOT / "Export/packages/cms-plugin-api-4.info",
    )
    host = output / "host"
    command = [
        str(compiler),
        *host_options(),
        "-cp",
        str(ROOT / "tests/haxe"),
        "-main",
        "plugins.CppiaHost",
        *host_exports(),
        "--cpp",
        str(host),
        "-D",
        "scriptable",
        "-dce",
        "no",
        "-D",
        "HXCPP_COMPILE_THREADS=4",
        "-D",
        "dll_export=" + str(host / "export_classes.info"),
    ]
    if platform.machine() == "arm64":
        command.extend(["-D", "HXCPP_ARM64"])
    subprocess.run(command, cwd=ROOT, check=True, env=environment)
    api = ROOT / "Export/packages/cms-plugin-api-4.info"
    with tempfile.TemporaryDirectory(prefix="cms-cppia-test-") as name:
        work = Path(name)
        source = ROOT / "examples/plugins/reading-companion/src/example/reading/ReadingPlugin.hx"
        original = "var message:String = input.settings.message;"
        text = source.read_text()
        assert original in text
        updated_source = work / "src/example/reading/ReadingPlugin.hx"
        updated_source.parent.mkdir(parents=True)
        updated_source.write_text(
            text.replace(
                original, 'var message:String = "Updated module: " + input.settings.message;'
            )
        )
        updated = work / "updated.cppia"
        subprocess.run(
            [
                str(compiler),
                *host_options(),
                "-cp",
                str(work / "src"),
                "-cp",
                str(ROOT / "src"),
                "--macro",
                'include("example")',
                *external_host_options(),
                "-D",
                "dll_import=" + str(api),
                "--cppia",
                str(updated),
            ],
            cwd=ROOT,
            check=True,
            env=environment,
        )
        invalid = work / "invalid.cppia"
        subprocess.run(
            [
                str(compiler),
                "-cp",
                str(ROOT / "tests/haxe"),
                "--macro",
                'haxe.macro.Context.getType("plugins.InvalidEntrypoint")',
                "-D",
                "dll_import=" + str(api),
                "--cppia",
                str(invalid),
            ],
            cwd=ROOT,
            check=True,
            env=environment,
        )
        manifest = json.loads(
            (ROOT / "examples/plugins/reading-companion/cms-package.json").read_text()
        )
        with ZipFile(ROOT / "Export/packages/reading-companion-2.16.0.zip") as sample:
            jar = sample.read("server.jar")
        minimal = {
            **manifest,
            "assets": {},
            "hooks": ["site.shared"],
            "translations": {},
            "server": {
                "jar": "server.jar",
                "cppia": "server.cppia",
                "entrypoint": "example.reading.ReadingPlugin",
            },
        }
        script = (ROOT / "Export/packages/reading-companion/server.cppia").read_bytes()
        modules = [("server.jar", jar), ("server.cppia", script)]
        cases = []

        def reject(label, data):
            cases.append({"name": label, "archive": base64.b64encode(data).decode()})

        reject(
            "JVM-only package",
            archive(
                {
                    **minimal,
                    "server": {"jar": "server.jar", "entrypoint": "example.reading.ReadingPlugin"},
                },
                [("server.jar", b"not executed")],
            ),
        )
        reject("missing module", archive(minimal, []))
        reject(
            "invalid bytecode",
            archive(minimal, [("server.jar", jar), ("server.cppia", b"invalid module")]),
        )
        reject("path traversal", archive(minimal, modules + [("../escape", "unsafe")]))
        reject("case duplicate", archive(minimal, modules + [("SERVER.CPPIA", script)]))
        oversized = bytearray(
            archive(minimal, modules + [("large.txt", b"a" * (16 * 1024 * 1024 + 1))])
        )
        position = oversized.find(b"large.txt") - 30
        struct.pack_into("<I", oversized, position + 22, 0)
        reject("false expanded length", oversized)
        block = b"a" * (12 * 1024 * 1024)
        reject(
            "total expanded size",
            archive(
                minimal,
                modules + [("expanded-" + str(index) + ".txt", block) for index in range(11)],
            ),
        )
        reject(
            "entry count",
            archive(minimal, modules + [("files/" + str(index), b"") for index in range(256)]),
        )
        corrupt = bytearray(archive(minimal, modules, compression=ZIP_STORED))
        position = corrupt.find(script)
        corrupt[position + len(script) - 1] ^= 1
        reject("checksum", corrupt)
        case_file = work / "cases.json"
        case_file.write_text(json.dumps(cases))
        (work / "storage/cache").mkdir(parents=True)
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
        (work / ".env").write_text(
            "".join(key + "=" + value + "\n" for key, value in values.items())
        )
        with FixtureStore(work) as fixtures:
            fixtures.call("initialize_schema")
            fixtures.create(
                "settings",
                [
                    {"key": key, "value": value}
                    for key, value in {
                        "site_name": "Native test",
                        "description": "Native feed",
                        "publisher_name": "Editor",
                        "about_site": "A writer",
                    }.items()
                ],
            )
            fixtures.create(
                "items",
                [
                    {
                        "title": "Native feed content item",
                        "slug": "native-feed",
                        "excerpt": "A native plugin feed.",
                        "content": "Private body",
                        "category": "",
                        "status": "published",
                        "published_at": "2026-11-03",
                        "created_at": "2026-11-03",
                        "updated_at": "2026-11-03",
                    }
                ],
            )
        feed_package = ROOT / "Export/packages/rss-2.16.0.zip"
        newsletter_package = ROOT / "Export/packages/newsletter-2.16.0.zip"
        binary = host / ("CppiaHost.exe" if os.name == "nt" else "CppiaHost")
        sample = ROOT / "Export/packages/reading-companion-2.16.0.zip"
        try:
            subprocess.run(
                [
                    str(binary),
                    str(sample),
                    str(updated),
                    str(work / "extracted"),
                    str(invalid),
                    str(case_file),
                    str(feed_package),
                    str(newsletter_package),
                ],
                cwd=work,
                check=True,
                env=environment,
            )
        except subprocess.CalledProcessError:
            failure = ROOT / "outputs/cppia-failure"
            if failure.exists():
                shutil.rmtree(failure)
            shutil.copytree(work, failure)
            print("Saved isolated CPPIA failure workspace: " + str(failure), flush=True)
            raise
        streamed = work / "streamed.zip"
        streamed.write_bytes(archive(minimal, modules, descriptor=True))
        subprocess.run(
            [
                str(binary),
                str(streamed),
                str(updated),
                str(work / "streamed"),
                str(invalid),
                str(case_file),
                str(feed_package),
                str(newsletter_package),
            ],
            cwd=work,
            check=True,
            env=environment,
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-packages", action="store_true")
    arguments = parser.parse_args()
    run(arguments.skip_packages)
