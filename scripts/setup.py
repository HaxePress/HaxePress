#!/usr/bin/env python3
"""Set up project-local Haxe/Crossbyte dependencies without changing global registrations."""

import base64
import json
import os
from pathlib import Path
import platform
import secrets
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "dependencies.lock.json").read_text())


def download_archive(url, dest):
    archive = ROOT / ".tools" / ("download-" + dest.name + ".tar.gz")
    archive.parent.mkdir(parents=True, exist_ok=True)
    print("Downloading " + dest.name + "…", flush=True)
    urllib.request.urlretrieve(url, archive)
    dest.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            parts = Path(member.name).parts
            if len(parts) < 2:
                continue
            member.name = str(Path(*parts[1:]))
            tar.extract(member, dest, filter="data")
    archive.unlink()


def main():
    compiler = ROOT / ".tools/haxe/haxe"
    if not compiler.exists() and not os.environ.get("HXWELL_HAXE"):
        suffix = {"Darwin": "osx", "Linux": "linux64"}.get(platform.system())
        if not suffix:
            raise SystemExit("Set HXWELL_HAXE to a Haxe 4.3.7 executable on this platform.")
        download_archive(
            "https://github.com/HaxeFoundation/haxe/releases/download/4.3.7/haxe-4.3.7-"
            + suffix
            + ".tar.gz",
            compiler.parent,
        )
    for name in ("crossbyte", "emitter", "hxwell-inertia"):
        dest = ROOT / ".deps" / name
        if not (dest / "haxelib.json").exists():
            entry = LOCK[name]
            download_archive(
                entry["repository"].replace("https://github.com/", "https://codeload.github.com/")
                + "/tar.gz/"
                + entry["commit"],
                dest,
            )
    repo = ROOT / ".haxelib"
    repo.mkdir(exist_ok=True)
    hxcpp_version = LOCK["hxcpp"]
    hxcpp = repo / "hxcpp" / hxcpp_version.replace(".", ",")
    if not (hxcpp / "haxelib.json").exists():
        subprocess.run(
            ["haxelib", "install", "hxcpp", hxcpp_version, "--quiet"], cwd=ROOT, check=True
        )
    global_repo = Path(
        subprocess.check_output(
            ["haxelib", "config"],
            cwd="/private/tmp" if platform.system() == "Darwin" else "/tmp",
            text=True,
        ).strip()
    )
    concurrent_source = global_repo / "haxe-concurrent" / LOCK["haxe-concurrent"].replace(".", ",")
    concurrent = ROOT / ".deps/haxe-concurrent"
    shutil.copytree(
        concurrent_source, concurrent, dirs_exist_ok=True, ignore=shutil.ignore_patterns(".git")
    )
    for filename in ["Acquirable.hx", "RLock.hx", "Semaphore.hx", "RWLock.hx"]:
        file = concurrent / "src/hx/concurrent/lock" / filename
        file.write_text(file.read_text())
    paths = {
        "haxe-concurrent": concurrent,
        "hxcpp": hxcpp,
        "hxwell": Path(os.environ.get("HXWELL_PATH", str(ROOT.parent / "hxwell"))),
        "hxwell-crossbyte": Path(
            os.environ.get("HXWELL_CROSSBYTE_PATH", str(ROOT.parent / "hxwell-crossbyte"))
        ),
        "hxwell-inertia": ROOT / ".deps/hxwell-inertia",
        "crossbyte": ROOT / ".deps/crossbyte",
        "emitter": ROOT / ".deps/emitter",
    }
    framework_source = paths["hxwell"].resolve()
    framework = ROOT / ".deps/hxwell"
    if not (framework_source / "haxelib.json").exists():
        raise SystemExit("Missing hxwell checkout: " + str(framework_source))
    if framework_source != framework.resolve():
        framework.mkdir(parents=True, exist_ok=True)
        for folder in ("src", "resource", "resources", "template", "tools"):
            source = framework_source / folder
            if source.exists():
                shutil.copytree(source, framework / folder, dirs_exist_ok=True)
        for filename in ("haxelib.json", "extraParams.hxml", "run.n", "LICENSE"):
            shutil.copy2(framework_source / filename, framework / filename)
    paths["hxwell"] = framework
    driver_source = paths["hxwell-crossbyte"].resolve()
    driver = ROOT / ".deps/hxwell-crossbyte"
    if driver_source != driver.resolve():
        driver.mkdir(parents=True, exist_ok=True)
        shutil.copytree(driver_source / "src", driver / "src", dirs_exist_ok=True)
        for filename in ("haxelib.json", "extraParams.hxml", "LICENSE"):
            if (driver_source / filename).exists():
                shutil.copy2(driver_source / filename, driver / filename)
    paths["hxwell-crossbyte"] = driver
    standard_library = ROOT / ".tools/haxe/std"
    if not standard_library.exists():
        custom_compiler = Path(os.environ.get("HXWELL_HAXE", str(compiler))).resolve()
        source_library = custom_compiler.parent / "std"
        if not source_library.exists():
            raise SystemExit("The Haxe 4.3.7 standard library is required beside its compiler.")
        shutil.copytree(source_library, standard_library)
    for package, filename in [
        ("hxwell", "hxwell-query-builder.patch"),
        ("hxwell", "hxwell-config-package.patch"),
        ("hxwell", "hxwell-plugin-routes.patch"),
        ("hxwell", "hxwell-cache-bytes.patch"),
        ("hxwell", "hxwell-map-tools.patch"),
        ("hxwell", "hxwell-websocket-sessions.patch"),
        ("hxwell", "hxwell-env-literals.patch"),
        ("hxwell-crossbyte", "hxwell-crossbyte-sessions.patch"),
        ("haxe-concurrent", "haxe-concurrent-cppia.patch"),
        ("hxwell-inertia", "hxwell-inertia.patch"),
        ("crossbyte", "crossbyte-ascii-headers.patch"),
        ("haxe-std", "haxe-jdbc-autocommit.patch"),
        ("haxe-std", "haxe-jdbc-column-labels.patch"),
        ("haxe-std", "haxe-jdbc-value-types.patch"),
        ("haxe-std", "haxe-mysql-connection.patch"),
        ("hxcpp", "hxcpp-macos-zlib.patch"),
    ]:
        patch = ROOT / "patches" / filename
        if patch.exists():
            target = standard_library if package == "haxe-std" else paths[package]
            patch_env = os.environ.copy()
            patch_env["GIT_CEILING_DIRECTORIES"] = str(target.parent.resolve())
            applied = (
                subprocess.run(
                    ["git", "apply", "--reverse", "--check", str(patch)],
                    cwd=target,
                    env=patch_env,
                    capture_output=True,
                ).returncode
                == 0
            )
            if not applied:
                subprocess.run(["git", "apply", str(patch)], cwd=target, env=patch_env, check=True)
    for name in ("haxe-concurrent", "crypto", "uuid", "hxjava", "formatter"):
        version = LOCK[name]
        path = global_repo / name / version.replace(".", ",")
        if not (path / "haxelib.json").exists():
            raise SystemExit(
                "Install the prerequisite first: haxelib install " + name + " " + version
            )
        paths[name] = concurrent if name == "haxe-concurrent" else path
    repo = ROOT / ".haxelib"
    repo.mkdir(exist_ok=True)
    for name, path in paths.items():
        path = path.resolve()
        if not (path / "haxelib.json").exists():
            raise SystemExit("Missing " + name + " checkout: " + str(path))
        entry = repo / name
        entry.mkdir(exist_ok=True)
        (entry / ".dev").write_text(str(path) + "\n")
        version = json.loads((path / "haxelib.json").read_text())["version"]
        link = entry / version.replace(".", ",")
        if not link.exists():
            link.symlink_to(path, target_is_directory=True)
        (entry / ".current").write_text(version + "\n")
    for name in ("sessions", "cache"):
        (ROOT / "storage" / name).mkdir(parents=True, exist_ok=True)
    for library, entry in LOCK.items():
        if not isinstance(entry, dict) or not entry.get("url", "").endswith(".jar"):
            continue
        target = ROOT / "java-lib" / (library + "-" + entry["version"] + ".jar")
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            print("Downloading " + library + "…", flush=True)
            urllib.request.urlretrieve(entry["url"], target)
    subprocess.run(["haxelib", "fixrepo"], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    if not (ROOT / ".env").exists():
        text = (
            (ROOT / ".env.example")
            .read_text()
            .replace("APP_KEY=", "APP_KEY=" + base64.b64encode(secrets.token_bytes(32)).decode())
        )
        (ROOT / ".env").write_text(text)
        (ROOT / ".env").chmod(0o600)
        print(
            "Created private .env. Start the site and open /admin/install from 127.0.0.1. Configure INSTALL_TRUSTED_IPS for other addresses."
        )
    config = ROOT / ".env"
    content = config.read_text()
    keys = {
        line.split("=", 1)[0].strip()
        for line in content.splitlines()
        if "=" in line and not line.lstrip().startswith("#")
    }
    defaults = {
        "VITE_USE_BUILD": "true",
        "INERTIA_SSR_ENABLED": "true",
        "INERTIA_SSR_URL": "http://127.0.0.1:13714/render",
        "INERTIA_SSR_TIMEOUT": "3",
    }
    for key, value in defaults.items():
        if key not in keys:
            if content and not content.endswith("\n"):
                content += "\n"
            content += key + "=" + value + "\n"
    config.write_text(content)
    config.chmod(0o600)
    print(
        "Project-local Haxe, Crossbyte, and Inertia are ready. Global Haxelib registrations are unchanged."
    )


if __name__ == "__main__":
    main()
