"""Verify native routes, lifecycle failures, strict releases and optional feature packages."""

import json
import os
from pathlib import Path
import sys
import tempfile
import zipfile

from e2e import Client, check
from cms_content import props
from cms_packages import install, zip_bytes
from fixture_store import FixtureStore

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_packages import build_plugin


def run():
    owner = Client()
    public = Client()
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
        "lifecycle owner login",
    )
    with FixtureStore.from_environment() as fixtures:
        check(public.request("/rss.xml")[0] == 200, "RSS plugin did not create its route")
        check(
            owner.request("/admin/plugins/plugin-rss/disable", "POST", {})[0] == 303, "disable RSS"
        )
        check(public.request("/rss.xml")[0] == 404, "disabled RSS route remained registered")
        check(
            not props(public, "/")["pluginNavigation"]["footer"],
            "disabled RSS footer link remained",
        )
        check(owner.request("/admin/plugins/plugin-rss/enable", "POST", {})[0] == 303, "enable RSS")
        check(public.request("/rss.xml")[0] == 200, "RSS route could not be recreated")
        subscribers = fixtures.count("subscribers")
        owner.request("/admin/plugins/plugin-newsletter/disable", "POST", {})
        check(
            public.request("/subscribe", "POST", {"email": "inactive@example.test"})[0] == 404,
            "disabled newsletter accepted a subscription",
        )
        check(
            owner.request("/admin/subscribers")[0] == 404,
            "disabled newsletter admin route remained",
        )
        check(
            not props(owner, "/admin")["pluginNavigation"]["admin"],
            "disabled newsletter menu remained",
        )
        check(
            all(
                asset["id"] != "plugin-newsletter"
                for asset in props(public, "/")["extensions"]["assets"]
            ),
            "disabled newsletter assets remained",
        )
        owner.request("/admin/plugins/plugin-newsletter/enable", "POST", {})
        check(
            owner.request("/admin/subscribers")[0] == 200, "newsletter admin route did not return"
        )
        check(
            fixtures.count("subscribers") == subscribers, "newsletter toggle lost subscriber data"
        )

        with zipfile.ZipFile(ROOT / "Export/packages/reading-companion-2.16.0.zip") as package:
            manifest = json.loads(package.read("cms-package.json"))
            files = {
                name: package.read(name)
                for name in package.namelist()
                if name != "cms-package.json"
            }
        for incompatible in [
            {**manifest, "cmsVersion": "2.8.1"},
            {**manifest, "cmsVersion": "^2.16.0"},
            {key: value for key, value in manifest.items() if key != "cmsVersion"},
            {
                **manifest,
                "server": {"jar": "server.jar", "entrypoint": manifest["server"]["entrypoint"]},
            },
            {
                **manifest,
                "server": {"cppia": "server.cppia", "entrypoint": manifest["server"]["entrypoint"]},
            },
        ]:
            status, _, body = owner.request(
                "/admin/plugins/upload",
                "POST",
                raw=zip_bytes(incompatible, files),
                content_type="application/zip",
            )
            check(status == 422, "incompatible/single-target package accepted: " + body[:150])
        php_definition = json.loads(files["php/module.json"])
        php_class = "php/" + next(iter(php_definition["classes"].values()))
        for missing in ["server.jar", "server.cppia", "php/module.json", php_class]:
            status, _, _ = owner.request(
                "/admin/plugins/upload",
                "POST",
                raw=zip_bytes(
                    manifest, {key: value for key, value in files.items() if key != missing}
                ),
                content_type="application/zip",
            )
            check(status == 422, "ZIP missing " + missing + " was accepted")
        for definition in [
            {**php_definition, "namespace": "cms"},
            {**php_definition, "entrypoint": "example.reading.OtherPlugin"},
            {**php_definition, "classes": {"hx.press.SiteSettingsStore": "lib/Store.php"}},
            {
                **php_definition,
                "classes": {name: "../escape.php" for name in php_definition["classes"]},
            },
        ]:
            status, _, _ = owner.request(
                "/admin/plugins/upload",
                "POST",
                raw=zip_bytes(manifest, {**files, "php/module.json": json.dumps(definition)}),
                content_type="application/zip",
            )
            check(status == 422, "An unsafe PHP class map was accepted")

        with tempfile.TemporaryDirectory(prefix="cms-lifecycle-package-") as name:
            path = build_plugin(
                ROOT / "tests/plugins/lifecycle",
                Path(name),
                ROOT / "Export/packages/cms-plugin-api-4.info",
            )
            package = path.read_bytes()
        identifier = "plugin-lifecycle-test"
        install(owner, "plugins", package)
        owner.request(
            "/admin/plugins/" + identifier + "/settings",
            "POST",
            {"fail_create": "true", "fail_destroy": "false"},
        )
        check(
            owner.request("/admin/plugins/" + identifier + "/enable", "POST", {})[0] == 422,
            "creation failure was swallowed",
        )
        row = fixtures.rows(
            "cms_packages",
            ["id", "enabled", "restart_required", "last_error"],
            [("id", "=", identifier)],
            limit=1,
        )[0]
        check(
            row["enabled"] == 0
            and row["restart_required"] == 1
            and "creation" in row["last_error"],
            "creation warning was not persisted",
        )
        check(public.request("/plugin-lifecycle")[0] == 404, "failed creation leaked a route")
        check(
            props(owner, "/admin/plugins")["pluginRestartRequired"],
            "creation failure did not warn about restart",
        )
        owner.request("/admin/plugins/" + identifier + "/uninstall", "POST", {})

        install(owner, "plugins", package)
        check(
            owner.request("/admin/plugins/" + identifier + "/enable", "POST", {})[0] == 303,
            "healthy creation failed",
        )
        check(
            public.request("/plugin-lifecycle")[0] == 200,
            "onCreate did not register a native route",
        )
        check(
            public.request("/admin/plugin-lifecycle")[0] == 303,
            "plugin admin route bypassed authentication",
        )
        check(
            owner.request("/admin/plugin-lifecycle")[0] == 200,
            "protected native plugin route failed",
        )
        check(
            owner.request("/admin/plugins/" + identifier + "/disable", "POST", {})[0] == 303,
            "healthy destruction failed",
        )
        check(public.request("/plugin-lifecycle")[0] == 404, "onDestroy did not remove the route")
        check(
            owner.request("/admin/plugins/" + identifier + "/enable", "POST", {})[0] == 303,
            "route/name could not be registered again",
        )
        owner.request(
            "/admin/plugins/" + identifier + "/settings",
            "POST",
            {"fail_create": "false", "fail_destroy": "true"},
        )
        check(
            owner.request("/admin/plugins/" + identifier + "/disable", "POST", {})[0] == 422,
            "destruction failure was swallowed",
        )
        row = fixtures.rows(
            "cms_packages",
            ["id", "restart_required", "last_error"],
            [("id", "=", identifier)],
            limit=1,
        )[0]
        check(
            row["restart_required"] == 1 and "destruction" in row["last_error"],
            "destruction warning missing",
        )
        check(
            public.request("/plugin-lifecycle")[0] == 404,
            "destruction failure left managed routes live",
        )
        check(
            owner.request("/admin/plugins/" + identifier + "/enable", "POST", {})[0] == 422,
            "dirty plugin reactivated without restart",
        )
        owner.request("/admin/plugins/" + identifier + "/uninstall", "POST", {})
        check(
            props(owner, "/admin")["pluginRestartRequired"],
            "uninstall hid the process restart warning",
        )
        check(
            "server may not function as expected" in owner.request("/admin/plugins")[2],
            "restart warning is missing from rendered UI",
        )
        check(fixtures.count("subscribers") == subscribers, "lifecycle operations lost subscribers")
    print(
        "PASS Native plugin lifecycle: routes/auth, restart warnings, strict CMS versions, dual artifacts and optional RSS/newsletter",
        flush=True,
    )


if __name__ == "__main__":
    run()
