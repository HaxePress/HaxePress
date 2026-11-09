"""Verify that startup replaces an example whose shipped archive changed under the same version."""

import hashlib
import json
import os
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGES_ROOT = Path(os.environ.get("CMS_TEST_PACKAGES_PATH", ROOT / "private/packages"))
EXAMPLE = "theme-notebook"
VIEW = "views/Home.well.html"
MARKER = f"cms_example_{EXAMPLE}"
ACCENT = "#234567"
REMOVED = "theme-gallery"
# A bundled plugin installed by an earlier build may name a hook the host no longer offers.
PLUGIN = "plugin-view-count"
PLUGIN_MARKER = "cms_builtin_view-count"
REMOVED_HOOK = "content.viewed"


def installed(fixtures):
    rows = fixtures.rows(
        "cms_packages",
        ["directory", "settings", "enabled", "version"],
        [("id", "=", EXAMPLE)],
        limit=1,
    )
    if not rows:
        raise AssertionError(f"{EXAMPLE} is not installed.")
    return rows[0]


def prepare(fixtures, work):
    """Leaves Notebook as an earlier release did: the same version, older views and no digest."""
    package = installed(fixtures)
    settings = json.loads(package["settings"])
    settings["accent"] = ACCENT
    fixtures.update("cms_packages", {"settings": json.dumps(settings)}, [("id", "=", EXAMPLE)])
    view = work / "storage/extensions/installed" / package["directory"] / VIEW
    view.write_text(f"{view.read_text()}\n<p>Left by the previous release</p>\n")
    fixtures.delete("settings", [("key", "=", MARKER)])
    # A release before bundled themes were part of the application let the owner remove one.
    fixtures.delete("cms_packages", [("id", "=", REMOVED)])
    plugin = fixtures.rows("cms_packages", ["manifest"], [("id", "=", PLUGIN)], limit=1)[0]
    manifest = json.loads(plugin["manifest"])
    manifest["hooks"] = [REMOVED_HOOK, *manifest.get("hooks", [])]
    fixtures.update("cms_packages", {"manifest": json.dumps(manifest)}, [("id", "=", PLUGIN)])
    fixtures.delete("settings", [("key", "=", PLUGIN_MARKER)])
    return {
        "directory": package["directory"],
        "settings": settings,
        "enabled": package["enabled"],
        "version": package["version"],
    }


def verify(fixtures, work, expected):
    """Returns the directory of the replaced example."""
    package = installed(fixtures)
    if package["directory"] == expected["directory"]:
        raise AssertionError("Startup kept an example whose shipped archive changed.")
    version = json.loads((ROOT / "cms.json").read_text())["version"]
    archive = PACKAGES_ROOT / f"notebook-{version}.zip"
    with zipfile.ZipFile(archive) as shipped:
        view = shipped.read(VIEW)
    replaced = work / "storage/extensions/installed" / package["directory"] / VIEW
    if replaced.read_bytes() != view:
        raise AssertionError("The replaced example does not have the shipped views.")
    if json.loads(package["settings"]) != expected["settings"]:
        raise AssertionError("Replacing an example lost its settings.")
    if package["enabled"] != expected["enabled"] or package["version"] != expected["version"]:
        raise AssertionError("Replacing an example changed its activation or version.")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    markers = fixtures.rows("settings", ["value"], [("key", "=", MARKER)], limit=1)
    if [row["value"] for row in markers] != [digest]:
        raise AssertionError("The digest of the shipped example archive was not recorded.")
    restored = fixtures.rows("cms_packages", ["enabled"], [("id", "=", REMOVED)], limit=1)
    if [row["enabled"] for row in restored] != [0]:
        raise AssertionError("Startup did not reinstall a removed bundled theme as inactive.")
    plugin = fixtures.rows("cms_packages", ["manifest", "enabled"], [("id", "=", PLUGIN)], limit=1)
    hooks = json.loads(plugin[0]["manifest"]).get("hooks", []) if plugin else []
    if not plugin or plugin[0]["enabled"] != 1 or REMOVED_HOOK in hooks:
        raise AssertionError(
            "A plugin naming a removed hook was not replaced with its shipped build."
        )
    return package["directory"]


def verify_unchanged(fixtures, directory):
    if installed(fixtures)["directory"] != directory:
        raise AssertionError("Startup replaced an example whose shipped archive did not change.")
