#!/usr/bin/env python3
"""Run HxWell's own CLI with this project's isolated compiler and libraries."""

import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
compiler = Path(os.environ.get("HXWELL_HAXE", str(root / ".tools/haxe/haxe"))).resolve()
if not compiler.exists():
    raise SystemExit("Haxe 4.3.7 is required. Run python3 scripts/setup.py first.")
env = os.environ.copy()
env["PATH"] = f"{str(compiler.parent)}{os.pathsep}{env.get('PATH', '')}"
env["HAXE_STD_PATH"] = str(root / ".tools/haxe/std")
if subprocess.check_output([str(compiler), "--version"], env=env, text=True).strip() != "4.3.7":
    raise SystemExit("The Crossbyte driver requires the pinned Haxe 4.3.7 compiler.")
haxelib = shutil.which("haxelib", path=env["PATH"])
if not haxelib:
    raise SystemExit("Haxelib is required. Run python3 scripts/setup.py first.")
raise SystemExit(subprocess.call([haxelib, "run", "hxwell", *sys.argv[1:]], cwd=root, env=env))
