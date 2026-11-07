"""Use the installed HxWell compiler configuration while linking host types externally."""

import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
# The application types plugins link to, shared with the PHP application build.
HOST_API_TYPES = re.findall(
    r'Context\.getType\("([^"]+)"\)', (ROOT / "plugin-host.hxml").read_text()
)


def host_exports():
    options = []
    for name in HOST_API_TYPES:
        options.extend(["--macro", f'haxe.macro.Context.getType("{name}")'])
    return options


def compiler():
    return Path(os.environ.get("HXWELL_HAXE", ROOT / ".tools/haxe/haxe")).resolve()


def environment():
    binary = compiler()
    return {
        **os.environ,
        "PATH": f"{str(binary.parent)}{os.pathsep}{os.environ['PATH']}",
        "HAXE_STD_PATH": str(ROOT / ".tools/haxe/std"),
    }


def host_options():
    options = [
        "-cp",
        str(ROOT / ".deps/hxwell/src"),
        "-cp",
        str(ROOT / "src"),
        "-D",
        "cms_plugin",
        "-D",
        "hxwell_config_package=hx.press.config",
        "-D",
        "env_file=.env",
        "-D",
        "scriptable",
    ]
    for line in (ROOT / "common.hxml").read_text().splitlines():
        if not line.startswith("-resource "):
            continue
        argument = line.split(None, 1)[1]
        filename, name = argument.rsplit("@", 1)
        options.extend(["-resource", f"{str(ROOT / filename)}@{name}"])
    for line in (ROOT / ".deps/hxwell/extraParams.hxml").read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        option, value = line.split(None, 1)
        if option != "-main":
            options.extend([option, value])
    return options


def external_host_options():
    return ["--macro", 'exclude("hx.well",true)', "--macro", 'exclude("hx.press",true)']
