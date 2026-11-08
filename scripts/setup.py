#!/usr/bin/env python3
"""Set up project-local Haxe/Crossbyte dependencies without changing global registrations."""

import base64
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "dependencies.lock.json").read_text())


def prepare_environment(project_root):
    config = project_root / ".env"
    created = not config.exists()
    content = (ROOT / ".env.example").read_text() if created else config.read_text()
    values = {}
    for line in content.splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()

    existing_key = values.get("APP_KEY", "").split("#", 1)[0].strip().strip("\"'")
    if not existing_key:
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/hxwell.py"), "generate:key"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        generated_keys = [
            line.removeprefix("APP_KEY=").strip()
            for line in result.stdout.splitlines()
            if line.startswith("APP_KEY=")
        ]
        if result.returncode != 0 or len(generated_keys) != 1:
            raise SystemExit("HxWell could not generate the initial application key.")
        generated_key = generated_keys[0]
        try:
            valid_key = len(base64.b64decode(generated_key, validate=True)) == 32
        except ValueError:
            valid_key = False
        if not valid_key:
            raise SystemExit("HxWell did not return a valid application key.")
        lines = []
        for line in content.splitlines():
            if "=" in line and line.split("=", 1)[0].strip() == "APP_KEY":
                line = f"APP_KEY={generated_key}"
            lines.append(line)
        if "APP_KEY" not in values:
            lines.append(f"APP_KEY={generated_key}")
        content = f"{'\n'.join(lines)}\n"

    if not created and content == config.read_text():
        config.chmod(0o600)
        return False
    descriptor, temporary = tempfile.mkstemp(prefix=".env.setup-", dir=project_root, text=True)
    try:
        with os.fdopen(descriptor, "w") as output:
            output.write(content)
        os.replace(temporary, config)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return created


def download_archive(url, dest):
    archive = ROOT / ".tools" / (f"download-{dest.name}.tar.gz")
    archive.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {dest.name}…", flush=True)
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


def locked_source(name):
    entry = LOCK[name]
    destination = ROOT / ".deps" / (f"{name}-{entry['commit']}")
    if not (destination / "haxelib.json").is_file():
        repository = entry["repository"].replace(
            "https://github.com/", "https://codeload.github.com/"
        )
        download_archive(f"{repository}/tar.gz/{entry['commit']}", destination)
    return destination


def refresh_source(source, destination):
    if not (source / "haxelib.json").is_file():
        raise SystemExit(f"Missing {destination.name} checkout: {source}")
    if source.resolve() == destination.resolve():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=f"{destination.name}-copy-", dir=destination.parent
    ) as directory:
        temporary = Path(directory)
        staging = temporary / "source"
        staging.mkdir()
        for folder in (
            "src",
            "std",
            "compat",
            "resource",
            "resources",
            "template",
            "tools",
            "client",
        ):
            origin = source / folder
            if origin.exists():
                shutil.copytree(origin, staging / folder)
        for filename in ("haxelib.json", "extraParams.hxml", "run.n", "LICENSE"):
            origin = source / filename
            if origin.is_file():
                shutil.copy2(origin, staging / filename)

        # A clean copy excludes files introduced by the previous patch set.
        previous = temporary / "previous"
        if destination.exists() or destination.is_symlink():
            destination.rename(previous)
        try:
            staging.rename(destination)
        except OSError:
            if previous.exists() or previous.is_symlink():
                previous.rename(destination)
            raise


def main():
    maven = shutil.which("mvn")
    if not maven:
        raise SystemExit("Install Maven to resolve the JVM dependencies in pom.xml.")
    version = LOCK["haxe"]
    compiler_override = os.environ.get("HXWELL_HAXE")
    compiler = Path(compiler_override or ROOT / ".tools/haxe/haxe").resolve()
    if not compiler.is_file():
        if compiler_override:
            raise SystemExit(f"Haxe executable not found: {compiler}")
        suffix = {"Darwin": "osx", "Linux": "linux64"}.get(platform.system())
        if not suffix:
            raise SystemExit(f"Set HXWELL_HAXE to a Haxe {version} executable on this platform.")
        download_archive(
            f"https://github.com/HaxeFoundation/haxe/releases/download/{version}/haxe-{version}-{suffix}.tar.gz",
            compiler.parent,
        )
    environment = os.environ.copy()
    environment["PATH"] = f"{str(compiler.parent)}{os.pathsep}{environment.get('PATH', '')}"
    actual_version = subprocess.check_output(
        [str(compiler), "--version"], env=environment, text=True
    ).strip()
    if actual_version != version:
        raise SystemExit(f"Haxe {version} is required, found {actual_version}.")
    haxelib = shutil.which("haxelib", path=environment["PATH"])
    if not haxelib or not shutil.which("neko", path=environment["PATH"]):
        raise SystemExit("Haxelib and Neko are required to run the HxWell CLI.")

    repo = ROOT / ".haxelib"
    repo.mkdir(exist_ok=True)
    # Haxelib tools such as formatter ship CommonJS scripts.
    package_scope = repo / "package.json"
    if not package_scope.exists():
        package_scope.write_text('{"type": "commonjs"}\n')
    paths = {}
    for name in ("haxe-concurrent", "crypto", "uuid", "hxjava", "formatter", "hxcpp"):
        library_version = LOCK[name]
        path = repo / name / library_version.replace(".", ",")
        if not (path / "haxelib.json").is_file():
            if path.is_symlink():
                path.unlink()
            subprocess.run(
                [haxelib, "install", name, library_version, "--always", "--quiet"],
                cwd=ROOT,
                env=environment,
                check=True,
            )
        paths[name] = path

    concurrent = ROOT / ".deps/haxe-concurrent"
    refresh_source(paths["haxe-concurrent"], concurrent)
    for filename in ["Acquirable.hx", "RLock.hx", "Semaphore.hx", "RWLock.hx"]:
        file = concurrent / "src/hx/concurrent/lock" / filename
        file.write_text(file.read_text())
    paths["haxe-concurrent"] = concurrent

    overrides = {
        "hxwell": "HXWELL_PATH",
        "hxwell-crossbyte": "HXWELL_CROSSBYTE_PATH",
        "wellout": "WELLOUT_PATH",
    }
    for name in ("hxwell", "hxwell-crossbyte", "crossbyte", "emitter", "wellout"):
        override = os.environ.get(overrides[name]) if name in overrides else None
        source = Path(override).resolve() if override else locked_source(name)
        destination = ROOT / ".deps" / name
        refresh_source(source, destination)
        paths[name] = destination

    standard_library = ROOT / ".tools/haxe/std"
    if not standard_library.exists():
        source_library = compiler.parent / "std"
        if not source_library.exists():
            raise SystemExit(
                f"The Haxe {version} standard library is required beside its compiler."
            )
        shutil.copytree(source_library, standard_library)
    for package, filename in [
        ("hxwell", "hxwell-query-builder.patch"),
        ("hxwell", "hxwell-config-package.patch"),
        ("hxwell", "hxwell-plugin-routes.patch"),
        ("hxwell", "hxwell-response-slices.patch"),
        ("hxwell", "hxwell-request-allocations.patch"),
        ("hxwell", "hxwell-php-storage-paths.patch"),
        ("hxwell", "hxwell-storage-append.patch"),
        ("hxwell-crossbyte", "hxwell-crossbyte-sessions.patch"),
        ("hxwell-crossbyte", "hxwell-crossbyte-response-slices.patch"),
        ("haxe-concurrent", "haxe-concurrent-cppia.patch"),
        ("crossbyte", "crossbyte-ascii-headers.patch"),
        ("crossbyte", "crossbyte-request-body-limits.patch"),
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
    for name, path in paths.items():
        path = path.resolve()
        if not (path / "haxelib.json").exists():
            raise SystemExit(f"Missing {name} checkout: {str(path)}")
        entry = repo / name
        entry.mkdir(exist_ok=True)
        (entry / ".dev").write_text(f"{str(path)}\n")
        version = json.loads((path / "haxelib.json").read_text())["version"]
        link = entry / version.replace(".", ",")
        if not link.exists():
            link.symlink_to(path, target_is_directory=True)
        (entry / ".current").write_text(f"{version}\n")
    for name in ("sessions", "cache"):
        (ROOT / "storage" / name).mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            maven,
            "--batch-mode",
            "--no-transfer-progress",
            f"-Dmaven.repo.local={str(ROOT / '.tools/maven-cache')}",
            "generate-resources",
        ],
        cwd=ROOT,
        check=True,
    )
    # Earlier setups installed these WebP reader JARs directly into java-lib.
    for artifact in (
        "common-image",
        "common-io",
        "common-lang",
        "imageio-core",
        "imageio-metadata",
        "imageio-webp",
    ):
        (ROOT / "java-lib" / f"{artifact}-3.15.3.jar").unlink(missing_ok=True)
    if prepare_environment(ROOT):
        print(
            "Created private .env with HxWell's application key. Start the site and open /admin/install from 127.0.0.1. Configure INSTALL_TRUSTED_IPS for other addresses."
        )
    print(
        "Project-local Haxe, Crossbyte and Wellout are ready. Global Haxelib registrations are unchanged."
    )


if __name__ == "__main__":
    main()
