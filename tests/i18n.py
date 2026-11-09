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
    turkish = {"code": "tr", "name": "Türkçe", "direction": "ltr", "enabled": "1"}
    check(
        owner.request("/admin/languages/save", "POST", turkish)[0] == 303,
        "Turkish could not be added as a site language",
    )
    try:
        verify(public, owner)
    finally:
        owner.request("/admin/languages/default", "POST", {"code": "en"})
        owner.request("/admin/languages/tr/delete", "POST", {})


def verify(public, owner):
    with FixtureStore.from_environment() as fixtures:
        original_content = list(
            fixtures.scan("items", ["id", "title", "content", "slug", "status"])
        )
        initial = props(public, "/")
        check(initial["i18n"]["locale"] == "en", "default language changed")
        status, headers, html = public.request("/tr")
        check(
            status == 200 and '<html lang="tr" dir="ltr">' in html,
            "server-rendered document language",
        )
        check("Son içerikler" in html, "server-rendered translation")
        check(
            headers.get("content-language") == "tr" and "set-cookie" not in headers,
            "stateless language request",
        )
        translated = props(public, "/tr")["i18n"]
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
        # The administration follows the member's own language.
        check(
            owner.request("/admin/locale", "POST", {"locale": "tr"})[0] == 303,
            "admin language preference",
        )
        try:
            clear_content(Path(os.environ["TEST_CACHE_PATH"]))
            status, _, subscriber_page = owner.request("/admin/subscribers?lang=en")
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
            props(public, "/?lang=tr")["i18n"]["locale"] == "en", "a query chose the page language"
        )
        status, headers, _ = public.request("/en/content?page=2")
        check(
            status == 301 and headers["location"] == "/content?page=2",
            "the default language's prefix did not move to the address without it",
        )

        def render(locale):
            """What went wrong with a concurrent request for `locale`, or None."""
            status, headers, html = Client().request("/tr" if locale == "tr" else "/")
            if status != 200:
                return f"{locale}: status {str(status)}"
            expected = "Son içerikler" if locale == "tr" else "The latest content"
            language = headers.get("content-language")
            if expected not in html or language != locale:
                return f"{locale}: rendered in {str(language)}"
            return None

        # When request threads shared regular expressions, about one render
        # in 400 failed with status 500; 2,000 renders failed about 5 times.
        requests = ["tr", "en"] * 1000
        with ThreadPoolExecutor(max_workers=12) as executor:
            failures = [failure for failure in executor.map(render, requests) if failure]
        first_failures = ", ".join(failures[:5])
        check(
            not failures,
            f"{str(len(failures))} of {str(len(requests))} concurrent requests failed: {first_failures}",
        )
        # The same validation on eight threads inside the server, which shows a
        # shared regular expression on every run rather than now and then.
        status, _, body = Client().request("/__fixtures/concurrent-matches")
        thread_failures = (
            json.loads(body)["failures"] if status == 200 else [f"status {str(status)}"]
        )
        thread_summary = "; ".join(thread_failures)
        check(not thread_failures, f"threads shared regular expressions: {thread_summary}")
        check("set-cookie" not in public.request("/tr")[1], "a language page created a session")
        status, _, body = public.request("/tr/subscribe", "POST", {"email": "invalid"})
        check(
            status == 422 and json.loads(body)["error"] == "Geçerli bir e-posta adresi girin.",
            "native plugin translation under a language prefix",
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
        english_frame = props(owner, "/admin/themes/theme-notebook/preview")["preview"]["url"]
        check(
            '<html lang="en"' in owner.request(english_frame)[2],
            "a theme preview did not default to the site's language",
        )
        check(
            owner.request("/admin/locale", "POST", {"locale": "en"})[0] == 303,
            "admin language reset",
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
            catalogues = props(Client(), "/tr")["i18n"]["catalogues"]
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
                props(Client(), "/tr")["i18n"]["catalogues"][first_id]["Save content"]
                == "Güncel çeviri",
                "replacement kept a stale catalogue",
            )
            owner.request(f"/admin/plugins/{first_id}/disable", "POST", {})
            check(
                first_id not in props(Client(), "/tr")["i18n"]["catalogues"],
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

        # The site's default language applies to new visitors.
        try:
            check(
                owner.request("/admin/languages/default", "POST", {"code": "tr"})[0] == 303,
                "default language setting",
            )
            check(
                props(Client(), "/")["i18n"]["locale"] == "tr",
                "default locale did not apply to a new visitor",
            )
            check(
                props(Client(), "/en")["i18n"]["locale"] == "en",
                "a language prefix did not choose the page language",
            )
        finally:
            owner.request("/admin/languages/default", "POST", {"code": "en"})
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
