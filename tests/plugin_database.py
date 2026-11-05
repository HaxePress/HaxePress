"""Exercise plugin-owned models and migrations through real package lifecycle operations."""

import base64
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

from cms_packages import install
from e2e import Client, check
from fixture_store import FixtureStore, TEST_BINARY

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_packages import build_plugin


def run():
    package_root = ROOT / "Export/packages"
    package = build_plugin(
        ROOT / "tests/plugins/database",
        package_root,
        package_root / "cms-plugin-api-4.info",
        TEST_BINARY,
    )
    owner = Client()
    owner.request("/admin/login")
    check(
        owner.request(
            "/admin/login",
            "POST",
            {
                "email": os.environ["TEST_ADMIN_EMAIL"],
                "password": os.environ["TEST_ADMIN_PASSWORD"],
            },
        )[0]
        == 303,
        "Plugin database owner login",
    )
    identifier = "plugin-database-test"
    with FixtureStore.from_environment() as fixtures:
        fixtures.call("plugin_database_checks", packageRoot=str(package_root))
        archive = package.read_bytes()
        install(owner, "plugins", archive)
        check(
            owner.request("/admin/plugins/" + identifier + "/enable", "POST", {})[0] == 303,
            "Activate plugin-owned schema",
        )
        context = {
            "data": {
                "action": "write",
                "key": "lifecycle-record",
                "title": "Stored by a plugin model",
                "rating": 3,
                "scope": "content:1",
                "metadata": {"customFields": {"mood": "quiet"}, "count": 4},
            }
        }

        def dispatch(data=archive):
            return fixtures.call(
                "dispatch_package",
                archive=base64.b64encode(data).decode(),
                event="site.shared",
                context=context,
            )

        first = dispatch()
        check(first["entry"]["title"] == context["data"]["title"], "Native plugin model write")
        context["data"]["action"] = "read"
        owner.request("/admin/plugins/" + identifier + "/disable", "POST", {})
        owner.request("/admin/plugins/" + identifier + "/uninstall", "POST", {})
        check(
            fixtures.count(
                "plugin_values", [("plugin_id", "=", "database-test"), ("scope", "=", "content:1")]
            )
            == 1,
            "Uninstall removed plugin data",
        )
        check(
            fixtures.count("plugin_migrations", [("plugin_id", "=", "database-test")]) == 2,
            "Uninstall removed migration history",
        )
        install(owner, "plugins", archive)
        owner.request("/admin/plugins/" + identifier + "/enable", "POST", {})
        restored = dispatch()
        check(
            restored["entry"]["id"] == first["entry"]["id"]
            and restored["metadata"] == context["data"]["metadata"],
            "Plugin reinstall did not retain its model/metadata",
        )

        with tempfile.TemporaryDirectory(prefix="cms-plugin-db-upgrade-") as name:
            work = Path(name)
            plugin = work / "plugin"
            shutil.copytree(ROOT / "tests/plugins/database", plugin)
            manifest_file = plugin / "cms-package.json"
            manifest = json.loads(manifest_file.read_text())
            manifest["version"] = "2.8.1"
            manifest_file.write_text(json.dumps(manifest, indent=2) + "\n")
            source = plugin / "src/extensions/database/DatabasePlugin.hx"
            source.write_text(
                source.read_text().replace("SCHEMA_VERSION = 2", "SCHEMA_VERSION = 3")
            )
            update = build_plugin(
                plugin, work, package_root / "cms-plugin-api-4.info", TEST_BINARY
            ).read_bytes()
        install(owner, "plugins", update, replace=True)
        upgraded = dispatch(update)
        check(
            upgraded["hasUpgrade"] and upgraded["entry"]["id"] == first["entry"]["id"],
            "Plugin update did not migrate while preserving its data",
        )
        check(
            fixtures.count("plugin_migrations", [("plugin_id", "=", "database-test")]) == 3,
            "Plugin upgrade migration was not recorded exactly once",
        )
        owner.request("/admin/plugins/" + identifier + "/disable", "POST", {})
        owner.request("/admin/plugins/" + identifier + "/enable", "POST", {})
        check(
            fixtures.count("plugin_migrations", [("plugin_id", "=", "database-test")]) == 3,
            "Reactivation repeated an applied migration",
        )
        owner.request("/admin/plugins/" + identifier + "/disable", "POST", {})
        owner.request("/admin/plugins/" + identifier + "/uninstall", "POST", {})
    print(
        "PASS Plugin database lifecycle: owned models, schema upgrades, scoped metadata and retention across disable/uninstall/reinstall",
        flush=True,
    )


if __name__ == "__main__":
    run()
