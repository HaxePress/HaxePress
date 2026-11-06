"""Build version-specific JVM, CPPIA and PHP plugin ZIPs and the shared native SDK."""

import argparse
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
from uuid import UUID
from zipfile import ZipFile, ZIP_DEFLATED

from plugin_build import (
    ROOT,
    compiler,
    environment,
    host_options,
    external_host_options,
    host_exports,
)


def build_php_plugin(plugin, folder, manifest):
    namespace = manifest["server"]["entrypoint"].rsplit(".", 1)[0]
    prefix = f"CmsPlugin_{secrets.token_hex(16)}"
    generated = folder / "php-build"
    if generated.exists():
        shutil.rmtree(generated)
    subprocess.run(
        [
            str(compiler()),
            *host_options(),
            "-cp",
            str(plugin / "src"),
            "--macro",
            f'include("{namespace}")',
            "--macro",
            f'hx.press.plugins.PhpPluginBuild.configure("{namespace}","{prefix}")',
            *external_host_options(),
            "--php",
            str(generated),
        ],
        cwd=ROOT,
        env=environment(),
        check=True,
    )
    artifact = folder / manifest["server"]["php"]
    target = artifact.parent
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)
    classes = {}
    for source in sorted((generated / "lib" / prefix).rglob("*.php")):
        text = source.read_text()
        native_namespace = re.search(r"^namespace ([A-Za-z0-9_\\]+);", text, re.MULTILINE)
        declaration = re.search(
            r"^(?:abstract |final )?(?:class|interface) ([A-Za-z0-9_]+)", text, re.MULTILINE
        )
        if native_namespace is None or declaration is None:
            raise RuntimeError("The generated PHP module has an unsupported class declaration")
        name = f"{native_namespace[1]}\\{declaration[1]}"
        relative = source.relative_to(generated)
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        classes[name] = relative.as_posix()
    if not classes:
        raise RuntimeError("The PHP compiler did not emit any plugin classes")
    definition = {
        "namespace": prefix,
        "entrypoint": manifest["server"]["entrypoint"],
        "classes": classes,
    }
    artifact.write_text(f"{json.dumps(definition, indent=2)}\n")
    return target


def build_plugin(plugin, output, api_info, application=None):
    manifest = json.loads((plugin / "cms-package.json").read_text())
    identity = manifest.get("pluginId", "")
    try:
        identifier = UUID(identity)
    except (ValueError, TypeError, AttributeError):
        raise RuntimeError(f"{plugin.name} must declare a stable lowercase pluginId UUID") from None
    if str(identifier) != identity or identifier.version not in range(1, 9):
        raise RuntimeError(f"{plugin.name} must declare a stable lowercase pluginId UUID")
    base = [str(compiler()), *host_options()]
    namespace = manifest["server"]["entrypoint"].rsplit(".", 1)[0]
    folder = output / manifest["slug"]
    folder.mkdir(exist_ok=True)
    source = [
        *base,
        "-cp",
        str(plugin / "src"),
        "--macro",
        f'include("{namespace}")',
    ]
    jar = folder / "server.jar"
    jvm = [
        str(compiler()),
        str(ROOT / "global.hxml"),
        "-lib",
        "hxwell",
        "-lib",
        "hxjava",
        "-cp",
        str(plugin / "src"),
        "--macro",
        f'include("{namespace}")',
        "--jvm",
        str(jar),
    ]
    for library in sorted((ROOT / "java-lib").glob("*.jar")):
        jvm.extend(["-java-lib", str(library)])
    subprocess.run(jvm, cwd=ROOT, env=environment(), check=True)
    # Keep native Haxe/JVM calling conventions while omitting classes supplied by the host.
    host_jar = application or Path(
        os.environ.get("CMS_TEST_APPLICATION", ROOT / "Export/jvm/hxwell.jar")
    )
    with ZipFile(host_jar) as host:
        host_classes = {name for name in host.namelist() if name.endswith(".class")}
    thin = jar.with_suffix(".thin.jar")
    with ZipFile(jar) as generated, ZipFile(thin, "w", compression=ZIP_DEFLATED) as target:
        for entry in generated.infolist():
            if entry.filename in host_classes and not entry.filename.startswith("haxe/generated/"):
                continue
            target.writestr(entry, generated.read(entry.filename))
    thin.replace(jar)
    cppia = folder / "server.cppia"
    subprocess.run(
        [
            *source,
            *external_host_options(),
            "-D",
            f"dll_import={str(api_info)}",
            "--cppia",
            str(cppia),
        ],
        cwd=ROOT,
        env=environment(),
        check=True,
    )
    php = build_php_plugin(plugin, folder, manifest)
    package = output / (f"{manifest['slug']}-{manifest['version']}.zip")
    with ZipFile(package, "w", compression=ZIP_DEFLATED) as archive:
        archive.write(plugin / "cms-package.json", "cms-package.json")
        archive.write(jar, manifest["server"]["jar"])
        archive.write(cppia, manifest["server"]["cppia"])
        for source in sorted(php.rglob("*")):
            if source.is_file():
                archive.write(source, source.relative_to(folder))
        for catalogue in manifest.get("translations", {}).values():
            archive.write(plugin / catalogue, catalogue)
        for asset in sorted((plugin / "public").rglob("*")):
            if asset.is_file():
                archive.write(asset, asset.relative_to(plugin))
        views = manifest.get("assets", {}).get("views", "")
        if views:
            for template in sorted((plugin / views).rglob("*")):
                if template.is_file():
                    archive.write(template, template.relative_to(plugin))
    return package


def build(application, public_root=None):
    public_root = Path(public_root or os.environ.get("CMS_TEST_PUBLIC_PATH", ROOT / "public"))
    output = ROOT / "Export/packages"
    output.mkdir(parents=True, exist_ok=True)
    release = json.loads((ROOT / "cms.json").read_text())
    sdk_name = f"cms-plugin-api-{str(release['pluginApiVersion'])}"
    sdk = output / (f"{sdk_name}.jar")
    contracts = ["PluginEntrypoint", "PluginHost"]
    with ZipFile(application) as source, ZipFile(sdk, "w", compression=ZIP_DEFLATED) as target:
        target.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\n\n")
        for contract in contracts:
            name = f"hx/press/plugins/{contract}.class"
            target.writestr(name, source.read(name))
        response_contract = "hx/press/validation/ValidationResponder.class"
        target.writestr(response_contract, source.read(response_contract))
    api_info = output / (f"{sdk_name}.info")
    base = [str(compiler()), *host_options()]
    export = base + [
        "--cpp",
        str(output / "cpp-api"),
        "-D",
        "no-compilation",
        "-dce",
        "no",
        "-D",
        f"dll_export={str(api_info)}",
    ]
    export.extend(host_exports())
    subprocess.run(export, cwd=ROOT, env=environment(), check=True)
    info = api_info.read_text()
    for contract in contracts:
        if f"interface hx.press.plugins.{contract}" not in info:
            raise RuntimeError(f"The SDK export is missing {contract}")
    source_sdk = output / (f"{sdk_name}.zip")
    with ZipFile(source_sdk, "w", compression=ZIP_DEFLATED) as archive:
        for contract in [*contracts, "PhpPluginBuild", "PluginDatabase", "PluginMigration"]:
            path = Path("src/hx/press/plugins") / (f"{contract}.hx")
            archive.write(ROOT / path, path)
        public_sources = [
            "src/hx/press/validation/ValidationResponder.hx",
            "src/hx/press/content/ContentTypes.hx",
            "src/hx/press/content/ContentTypeDefinition.hx",
            "src/hx/press/content/ContentFields.hx",
            "src/hx/press/content/ContentLocks.hx",
            "src/hx/press/access/Roles.hx",
            "src/hx/press/navigation/NavigationRegions.hx",
            "src/hx/press/media/MediaReferences.hx",
            "src/hx/press/media/MediaDependencies.hx",
            "src/hx/press/media/MediaDependencyMode.hx",
            "src/hx/press/media/MediaLocks.hx",
            "src/hx/press/media/MediaUsage.hx",
            "src/hx/press/NavigationData.hx",
        ]
        for relative in public_sources:
            archive.write(ROOT / relative, relative)
        archive.write(api_info, "cppia-export.info")
        archive.write(ROOT / "cms.json", "cms.json")
    packages = []
    for plugin in sorted((ROOT / "examples/plugins").iterdir()):
        if not plugin.is_dir():
            continue
        manifest = json.loads((plugin / "cms-package.json").read_text())
        if (
            manifest["cmsVersion"] != release["version"]
            or manifest["apiVersion"] != release["pluginApiVersion"]
        ):
            raise RuntimeError(f"Rebuild {manifest['slug']} for this exact CMS release")
        package = build_plugin(plugin, output, api_info, application)
        packages.append(package)
    public_packages = public_root / "packages"
    public_packages.mkdir(parents=True, exist_ok=True)
    for artifact in [sdk, source_sdk, *packages]:
        shutil.copy2(artifact, public_packages / artifact.name)
    subprocess.run(
        ["node", "scripts/build_themes.mjs"],
        cwd=ROOT,
        check=True,
        env={**os.environ, "CMS_PUBLIC_PATH": str(public_root.resolve())},
    )
    for source in sorted((ROOT / "examples/themes").iterdir()):
        if not source.is_dir():
            continue
        theme = ROOT / "Export/themes" / source.name
        theme_manifest = json.loads((theme / "cms-package.json").read_text())
        package = output / (f"{theme.name}-{theme_manifest['version']}.zip")
        with ZipFile(package, "w", compression=ZIP_DEFLATED) as archive:
            for asset in sorted(theme.rglob("*")):
                if asset.is_file():
                    archive.write(asset, asset.relative_to(theme))
        shutil.copy2(package, public_packages / package.name)
    if public_root.resolve() == (ROOT / "public").resolve():
        deployment = ROOT / "Export/jvm/public/packages"
        deployment.mkdir(parents=True, exist_ok=True)
        for artifact in public_packages.iterdir():
            shutil.copy2(artifact, deployment / artifact.name)
        if (public_root / "themes").is_dir():
            shutil.copytree(
                public_root / "themes", ROOT / "Export/jvm/public/themes", dirs_exist_ok=True
            )
    print(
        (
            f"Built CMS {release['version']} native plugin SDK and {str(len(packages))}"
            " JVM/CPPIA/PHP plugins"
        ),
        flush=True,
    )
    return output / (f"reading-companion-{release['version']}.zip")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--application",
        type=Path,
        default=Path(os.environ.get("CMS_TEST_APPLICATION", ROOT / "Export/jvm/hxwell.jar")),
    )
    parser.add_argument("--public-root", type=Path)
    arguments = parser.parse_args()
    build(arguments.application, arguments.public_root)
