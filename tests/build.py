"""Compile the integration server and fixture process with the pinned JVM compiler."""

import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def build():
    compiler = Path(os.environ.get("HXWELL_HAXE", str(ROOT / ".tools/haxe/haxe"))).resolve()
    environment = {
        **os.environ,
        "PATH": f"{str(compiler.parent)}{os.pathsep}{os.environ['PATH']}",
        "HAXE_STD_PATH": str(ROOT / ".tools/haxe/std"),
    }
    command = [
        str(compiler),
        "global.hxml",
        "-lib",
        "hxwell",
        "-lib",
        "hxjava",
        "-cp",
        "tests/haxe",
        "-D",
        "cms_tests",
        "--macro",
        'include("fixtures")',
        "--jvm",
        str(ROOT / "Export/tests/hxwell.jar"),
    ]
    for library in sorted((ROOT / "java-lib").glob("*.jar")):
        command.extend(["-java-lib", str(library)])
    subprocess.run(command, cwd=ROOT, env=environment, check=True)


if __name__ == "__main__":
    build()
