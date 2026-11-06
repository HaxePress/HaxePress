"""Exercise request-local translations, native helpers and ZIP catalogue lifecycles."""

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
from uuid import NAMESPACE_URL, uuid5
import zipfile

from cms_content import props
from cms_packages import install, zip_bytes
from e2e import Client, check
from fixture_store import FixtureStore
from content_cache import clear_content

ROOT = Path(__file__).resolve().parents[1]
HEADERS = {"X-Well-Data": "true", "Accept": "application/json"}


def run():
    public = Client()
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
        "translation owner login",
    )
    with FixtureStore.from_environment() as fixtures:
        original_content = list(
            fixtures.scan("items", ["id", "title", "content", "slug", "status"])
        )
        initial = props(public, "/")
        check(initial["i18n"]["locale"] == "en", "default language changed")
        status, headers, html = public.request("/?lang=tr")
        check(
            status == 200 and '<html lang="tr" dir="ltr">' in html,
            "server-rendered document language",
        )
        check("Son içerikler" in html, "server-rendered translation")
        check(
            headers.get("content-language") == "tr" and "set-cookie" not in headers,
            "stateless language request",
        )
        translated = props(public, "/?lang=tr")["i18n"]
        check(
            translated["catalogues"]["plugin-newsletter"]["Subscribe"] == "Abone ol",
            "newsletter catalogue",
        )
        check("plugin-rss" in translated["catalogues"], "RSS catalogue")
        subscribers = fixtures.create(
            "subscribers",
            [
                {
                    "email": f"translated-pagination-{str(index)}@example.test",
                    "created_at": "2026-11-04 00:00:00",
                }
                for index in range(31)
            ],
        )
        try:
            clear_content(Path(os.environ["TEST_CACHE_PATH"]))
            status, _, subscriber_page = owner.request("/admin/subscribers?lang=tr")
            check(
                status == 200
                and "Aboneler" in subscriber_page
                and "abone içinden 30" in subscriber_page,
                "plugin pagination lost its translation namespace",
            )
        finally:
            fixtures.delete("subscribers", [("id", "in", subscribers)])
            clear_content(Path(os.environ["TEST_CACHE_PATH"]))
        check(
            props(public, "/?lang=unsupported")["i18n"]["locale"] == "en", "unknown locale fallback"
        )

        def render(locale):
            status, headers, html = Client().request(f"/?lang={locale}")
            expected = "Son içerikler" if locale == "tr" else "The latest content"
            return status == 200 and expected in html and headers["content-language"] == locale

        with ThreadPoolExecutor(max_workers=6) as executor:
            check(
                all(executor.map(render, ["tr", "en"] * 8)), "concurrent requests shared a language"
            )
        check(
            public.request("/locale", "POST", {"locale": "tr", "return_to": "/content"})[0] == 303,
            "language preference",
        )
        check(set(public.cookies) == {"cms_locale"}, "language selection created a session")
        check(props(public, "/")["i18n"]["locale"] == "tr", "language cookie was ignored")
        status, _, body = public.request("/subscribe", "POST", {"email": "invalid"})
        check(
            status == 422 and json.loads(body)["error"] == "Geçerli bir e-posta adresi girin.",
            "native plugin translation",
        )
        check(
            public.request("/locale", "POST", {"locale": "../tr"})[0] == 422,
            "invalid language accepted",
        )
        redirected = public.request(
            "/locale", "POST", {"locale": "en", "return_to": "//outside.example"}
        )
        check(
            redirected[0] == 303 and redirected[1]["location"] == "/",
            "language endpoint redirects outside the site",
        )
        preview_page = props(owner, "/admin/themes/theme-notebook/preview?lang=tr")
        preview_html = owner.request("/admin/themes/theme-notebook/preview?lang=tr")[2]
        check(
            preview_page["preview"]["name"] == "Defter" and "Defter" in preview_html,
            "inactive theme catalogue was not used in preview",
        )
        frame_status, _, frame = owner.request(preview_page["preview"]["url"])
        check(
            frame_status == 200
            and '<html lang="tr" dir="ltr">' in frame
            and props(owner, preview_page["preview"]["url"])["theme"]["id"] == "theme-notebook",
            "inactive theme preview frame did not render in the selected language",
        )
        check(
            props(Client(), "/")["theme"]["slug"] == "simple",
            "theme preview changed the active theme",
        )

        sample = ROOT / "Export/packages/reading-companion-2.16.0.zip"
        with zipfile.ZipFile(sample) as archive:
            binaries = {name: archive.read(name) for name in ["server.jar", "server.cppia"]}
        base = {
            "apiVersion": 4,
            "cmsVersion": "2.16.0",
            "kind": "plugin",
            "name": "Translation test",
            "version": "2.16.0",
            "fields": [],
            "server": {
                "jar": "server.jar",
                "cppia": "server.cppia",
                "entrypoint": "example.reading.ReadingPlugin",
            },
            "translations": {"en": "lang/en.json", "tr": "lang/tr.json"},
        }

        def package(slug, text, version="2.16.0"):
            manifest = {
                **base,
                "slug": slug,
                "version": version,
                "pluginId": str(uuid5(NAMESPACE_URL, f"haxepress-test:{slug}")),
            }
            return zip_bytes(
                manifest,
                {
                    **binaries,
                    "lang/en.json": json.dumps(
                        {"Fallback only": "Package fallback", "Hello {name}": "Hello {name}"}
                    ),
                    "lang/tr.json": json.dumps(
                        {
                            "Save content": text,
                            "Hello {name}": "Merhaba {name}",
                            "Items": {"one": "{count} kayıt", "other": "{count} kayıt"},
                        }
                    ),
                },
            )

        first_id = "plugin-translation-first"
        second_id = "plugin-translation-second"
        try:
            for slug, text in [
                ("translation-first", "Birinci eklenti"),
                ("translation-second", "İkinci eklenti"),
            ]:
                install(owner, "plugins", package(slug, text))
                check(
                    owner.request(f"/admin/plugins/plugin-{slug}/enable", "POST", {})[0] == 303,
                    "activate translation package",
                )
            catalogues = props(Client(), "/?lang=tr")["i18n"]["catalogues"]
            check(catalogues[first_id]["Save content"] == "Birinci eklenti", "first namespace")
            check(catalogues[second_id]["Save content"] == "İkinci eklenti", "second namespace")
            check(
                catalogues["cms"]["Save content"] == "İçeriği kaydet",
                "a plugin overwrote core translations",
            )
            check(
                catalogues[first_id]["Fallback only"] == "Package fallback",
                "package fallback catalogue",
            )
            native = lambda key, parameters=None: fixtures.call(
                "translate", key=key, parameters=parameters or {}, namespace=first_id, locale="tr"
            )
            check(native("Hello {name}", {"name": "Ada"}) == "Merhaba Ada", "native placeholders")
            check(native("Items", {"count": 3}) == "3 kayıt", "native plural messages")
            check(native("Fallback only") == "Package fallback", "native fallback")
            check(native("missing.key") == "missing.key", "missing key fallback")
            check(
                fixtures.call(
                    "translate",
                    key="Content count",
                    parameters={"count": 1},
                    namespace="cms",
                    locale="en",
                )
                == "1 content item",
                "English singular",
            )
            check(
                fixtures.call(
                    "translate",
                    key="Content count",
                    parameters={"count": 2},
                    namespace="cms",
                    locale="en",
                )
                == "2 content items",
                "English plural",
            )
            install(
                owner,
                "plugins",
                package("translation-first", "Güncel çeviri", "2.8.1"),
                replace=True,
            )
            check(
                props(Client(), "/?lang=tr")["i18n"]["catalogues"][first_id]["Save content"]
                == "Güncel çeviri",
                "replacement kept a stale catalogue",
            )
            owner.request(f"/admin/plugins/{first_id}/disable", "POST", {})
            check(
                first_id not in props(Client(), "/?lang=tr")["i18n"]["catalogues"],
                "disabled translations remain public",
            )
            owner.request(f"/admin/plugins/{first_id}/enable", "POST", {})

            invalid = [
                ({**base, "slug": "bad-catalogue", "translations": {"tr": "../escape.json"}}, {}),
                ({**base, "slug": "bad-catalogue"}, {"lang/en.json": "{}"}),
                (
                    {**base, "slug": "bad-catalogue"},
                    {"lang/en.json": "{}", "lang/tr.json": '{"Bad":{"one":"Only one"}}'},
                ),
                (
                    {**base, "slug": "bad-catalogue"},
                    {"lang/en.json": "{}", "lang/tr.json": '{"Bad":42}'},
                ),
            ]
            for manifest, files in invalid:
                status, _, _ = owner.request(
                    "/admin/plugins/upload",
                    "POST",
                    raw=zip_bytes(manifest, {**binaries, **files}),
                    content_type="application/zip",
                )
                check(status == 422, "invalid translation catalogue was accepted")
        finally:
            for identifier in [first_id, second_id]:
                owner.request(f"/admin/plugins/{identifier}/uninstall", "POST", {})

        original_settings = props(owner, "/admin/settings")["site"]
        try:
            check(
                owner.request("/admin/settings", "POST", {**original_settings, "locale": "tr"})[0]
                == 303,
                "default locale setting",
            )
            check(
                props(Client(), "/")["i18n"]["locale"] == "tr",
                "default locale did not apply to a new visitor",
            )
            check(
                props(Client(), "/?lang=en")["i18n"]["locale"] == "en",
                "explicit language did not override the default",
            )
        finally:
            owner.request("/admin/settings", "POST", original_settings)
        check(
            list(fixtures.scan("items", ["id", "title", "content", "slug", "status"]))
            == original_content,
            "translation changed editorial content",
        )
    print(
        "PASS Translation system: English/Turkish server rendering, request isolation, session-free preferences, native/plugin/theme namespaces, fallbacks/plurals, catalogue validation and replacement",
        flush=True,
    )


if __name__ == "__main__":
    run()
