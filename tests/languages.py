"""Verify the site languages: the Languages page, the MCP tools and each member's admin language.

A site starts with one language. The Languages page adds, edits, orders,
disables and deletes the others and chooses the default one; the admin
MCP tools do the same through the page's routes. The administration
language is each member's own choice and does not change the public site.
"""

import os
import re

from admin_mcp import call, issue, refused, succeeded, tool_names
from cms_content import props
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore

PAGE = "/admin/languages"


def languages(client):
    return props(client, PAGE)["siteLanguages"]


def codes(client):
    return [language["code"] for language in languages(client)]


def save(client, data, expected=303):
    values = {"direction": "ltr", "enabled": "1", "home_page_id": "0", "original_code": ""}
    values.update(data)
    status, headers, body = client.request(f"{PAGE}/save", "POST", values)
    check(status == expected, f"Saving a language returned {status}: {body[:300]}")
    return headers, body


def verify_page(owner):
    initial = languages(owner)
    check(
        [(item["code"], item["isDefault"], item["enabled"]) for item in initial]
        == [("en", True, True)],
        f"A new site did not start with one public default language: {initial}",
    )
    page = props(owner, "/admin/settings")
    check(
        page["languageCount"] == 1 and page["defaultLanguage"] == "English",
        "The settings page did not summarize the site's language",
    )
    check(
        "locale" not in page["settingsForm"],
        "The settings form still offers the old default language field",
    )

    save(owner, {"code": "de", "name": "Deutsch"})
    check(codes(owner) == ["en", "de"], "An added language was not listed after the default one")
    added = languages(owner)[1]
    check(
        not added["isDefault"] and added["enabled"] and added["address"] == "/de/",
        f"An added language had the wrong state: {added}",
    )

    for data, reason in [
        ({"code": "DE", "name": "Deutsch"}, "an uppercase language"),
        ({"code": "de_DE", "name": "Deutsch"}, "an underscore"),
        ({"code": "de", "name": "Deutsch"}, "a duplicate code"),
        ({"code": "api", "name": "API"}, "a reserved address"),
        ({"code": "fr", "name": ""}, "an empty name"),
        ({"code": "fr", "name": "Français", "direction": "up"}, "an unknown direction"),
        ({"code": "fr", "name": "Français", "home_page_id": "999999"}, "missing content"),
        (
            {"code": "en", "name": "English", "enabled": "0", "original_code": "en"},
            "a disabled default",
        ),
    ]:
        _, body = save(owner, data, 422)
        check(codes(owner) == ["en", "de"], f"A language with {reason} was saved")

    save(owner, {"code": "pt-BR", "name": "Português", "enabled": "0"})
    brazilian = next(item for item in languages(owner) if item["code"] == "pt-BR")
    check(
        brazilian["segment"] == "pt-br" and not brazilian["enabled"],
        f"A language with a region was not stored as a disabled language: {brazilian}",
    )
    save(owner, {"code": "pt", "name": "Português", "enabled": "1", "original_code": "pt-BR"})
    check(codes(owner) == ["en", "de", "pt"], "Changing a language's code lost its place")

    status, _, _ = owner.request(f"{PAGE}/order", "POST", {"order": "pt,en"})
    check(status == 422, "An order that left out a language was saved")
    status, _, _ = owner.request(f"{PAGE}/order", "POST", {"order": "pt,en,de"})
    check(status == 303 and codes(owner) == ["pt", "en", "de"], "The language order was not saved")

    status, _, _ = owner.request(f"{PAGE}/default", "POST", {"code": "de"})
    check(status == 303, "Choosing a default language failed")
    defaults = [item["code"] for item in languages(owner) if item["isDefault"]]
    check(defaults == ["de"], f"The site had another number of default languages: {defaults}")
    status, _, _ = owner.request(f"{PAGE}/de/delete", "POST", {})
    check(status == 422 and "de" in codes(owner), "The default language was deleted")
    check(
        props(Client(), "/")["i18n"]["locale"] == "de",
        "Public pages did not use the default language",
    )

    status, _, _ = owner.request(f"{PAGE}/default", "POST", {"code": "en"})
    check(status == 303, "Choosing English as the default again failed")
    for code in ["pt", "de"]:
        status, _, body = owner.request(f"{PAGE}/{code}/delete", "POST", {})
        check(status == 303, f"Deleting an unused language returned {status}: {body[:200]}")
    check(codes(owner) == ["en"], "Deleted languages were still listed")
    print("PASS Languages page adds, validates, orders, defaults and deletes languages", flush=True)


def verify_admin_language(owner, email, password):
    public = Client()
    check(props(owner, "/admin")["i18n"]["locale"] == "en", "The admin did not start in English")
    status, headers, _ = owner.request("/admin/locale", "POST", {"locale": "tr", "return_to": PAGE})
    check(status == 303 and headers["location"] == PAGE, "Changing the admin language failed")
    check(props(owner, "/admin")["i18n"]["locale"] == "tr", "The admin language was not applied")
    with FixtureStore.from_environment() as store:
        stored = store.rows("admins", ["ui_language"], [("email", "=", email)], limit=1)
    check(stored[0]["ui_language"] == "tr", "The admin language was not kept on the account")
    check(
        props(public, "/")["i18n"]["locale"] == "en",
        "A member's admin language changed the public site",
    )

    # Another browser of the same member opens the admin in their language.
    other = login(email, password)
    check(props(other, "/admin")["i18n"]["locale"] == "tr", "A new session lost the admin language")
    status, headers, _ = owner.request(
        "/admin/locale", "POST", {"locale": "tr", "return_to": "https://example.test/"}
    )
    check(headers.get("location") == "/admin", "The admin language form redirected off the admin")
    status, _, _ = owner.request("/admin/locale", "POST", {"locale": "xx"})
    check(status == 422, "An unknown admin language was accepted")

    # The sign-in page uses the browser's language, then the choice made on it.
    visitor = Client()
    page = visitor.request(
        "/admin/login",
        extra_headers={"Accept-Language": "tr-TR,tr;q=0.9,en;q=0.8"},
    )[2]
    check('<html lang="tr"' in page, "The sign-in page ignored the browser's language")
    visitor.request("/admin/locale", "POST", {"locale": "en", "return_to": "/admin/login"})
    page = visitor.request("/admin/login", extra_headers={"Accept-Language": "tr"})[2]
    check('<html lang="en"' in page, "The sign-in page ignored the chosen language")
    owner.request("/admin/locale", "POST", {"locale": "en"})
    print("PASS Each member keeps their own admin language, apart from the site", flush=True)


def hrefs(html):
    return set(re.findall(r'href="([^"]+)"', html))


def verify_routing(owner):
    public = Client()
    single = public.request("/about")[2]
    check(
        'class="language-switcher"' not in single and "hreflang" not in single,
        "A single-language site showed language links",
    )
    check(public.request("/en/about")[0] == 404, "A single-language site served a language prefix")

    save(owner, {"code": "tr", "name": "Türkçe"})
    status, headers, html = public.request("/tr/about")
    check(
        status == 200 and '<html lang="tr"' in html and headers["content-language"] == "tr",
        f"A Turkish page was not served in Turkish: {status}",
    )
    links = hrefs(html)
    check(
        "/tr/about" in links, f"Site links did not keep the page's language: {sorted(links)[:20]}"
    )
    check(
        not any(link.startswith("/tr/media/") or link.startswith("/tr/build/") for link in links),
        "File links got a language prefix",
    )
    check(
        {"/about", "/tr/about"} <= links,
        "The language switcher did not link the page in each language",
    )
    check(public.request("/tr/admin")[0] == 404, "The administration was served under a prefix")
    status, _, feed = public.request("/tr/rss.xml")
    check(status == 200 and "<rss" in feed, "A plugin route was not served under a prefix")
    check(
        props(public, "/tr/content?q=welcome")["query"] == "welcome",
        "A prefixed address lost its query",
    )
    status, headers, _ = public.request("/en/about?x=1")
    check(
        status == 301 and headers["location"] == "/about?x=1",
        "The default language's prefix did not redirect",
    )
    check(public.request("/fr/about")[0] == 404, "An unknown language prefix was served")

    save(owner, {"code": "tr", "name": "Türkçe", "enabled": "0", "original_code": "tr"})
    status, headers, _ = public.request("/tr/about")
    check(
        status == 302 and headers["location"] == "/",
        f"A disabled language did not send visitors to the default language: {status}",
    )
    html = public.request("/about")[2]
    check('class="language-switcher"' not in html, "A disabled language was offered")
    status, _, body = owner.request(f"{PAGE}/tr/delete", "POST", {})
    check(status == 303, f"Deleting Turkish failed: {body[:200]}")
    print("PASS Languages are served under their prefix, and disabled ones redirect", flush=True)


def save_content(owner, slug, language, status="published", **extra):
    data = {
        "id": "",
        "title": f"Language fixture {slug}",
        "slug": slug,
        "excerpt": "An item that checks which languages show it.",
        "content": "## A fixture\n\nThis item checks which languages list and show it.",
        "category": props(owner, "/admin/content/new")["item"]["category"],
        "status": status,
        "image": "",
        "image_alt": "",
        "featured": "0",
        "published_at": "2026-11-05",
        "stay": "1",
        "tags": "",
        "language": language,
        **extra,
    }
    status_code, headers, body = owner.request("/admin/content/save", "POST", data)
    if status_code != 303:
        return status_code, None, body
    return status_code, int(re.search(r"/content/(\d+)/edit", headers["location"]).group(1)), body


def listed_slugs(path):
    return {item["slug"] for item in props(Client(), path)["items"]}


def verify_content(owner):
    save(owner, {"code": "tr", "name": "Türkçe"})
    _, shared, _ = save_content(owner, "language-shared", "en", all_languages="1")
    _, english, _ = save_content(owner, "language-english", "en")
    _, turkish, _ = save_content(owner, "language-turkce", "tr")
    query = "?q=Language%20fixture"
    check(
        listed_slugs(f"/content{query}") == {"language-shared", "language-english"},
        "The English list showed the wrong items",
    )
    check(
        listed_slugs(f"/tr/content{query}") == {"language-shared", "language-turkce"},
        "The Turkish list did not show its own items and the shared one",
    )
    status, _, body = save_content(
        owner, "language-paylasilan", "tr", status="draft", translation_of=str(shared)
    )
    check(status == 303, f"A translation could not be saved: {body[:300]}")
    check(
        "language-shared" in listed_slugs(f"/tr/content{query}"),
        "A draft translation hid the shared item",
    )
    status, translation, _ = save_content(
        owner, "language-paylasilan", "tr", translation_of=str(shared)
    )
    check(status != 303, "A second Turkish translation of the same item was saved")
    with FixtureStore.from_environment() as store:
        draft = store.rows("items", ["id"], [("slug", "=", "language-paylasilan")], limit=1)[0]
        groups = {
            row["id"]: row["translation_group"]
            for row in store.rows(
                "items",
                ["id", "translation_group"],
                [("id", "in", [shared, draft["id"]])],
                limit=2,
            )
        }
    check(
        groups[shared] != "" and groups[shared] == groups[draft["id"]],
        "A translation did not join the group of the item it translates",
    )
    data = {"id": str(draft["id"]), "translation_of": str(shared)}
    status, _, body = save_content(owner, "language-paylasilan", "tr", **data)
    check(status == 303, f"Publishing the translation failed: {body[:300]}")
    check(
        listed_slugs(f"/tr/content{query}") == {"language-paylasilan", "language-turkce"},
        "The published translation did not replace the shared item",
    )
    check(
        listed_slugs(f"/content{query}") == {"language-shared", "language-english"},
        "A translation appeared in the English list",
    )
    status, headers, _ = Client().request("/tr/content/language-shared")
    check(
        status == 301 and headers["location"] == "/tr/content/language-paylasilan",
        "The shared address did not move to the translation",
    )
    check(
        Client().request("/tr/content/language-english")[0] == 404,
        "An English item was shown in Turkish",
    )
    status, _, page = Client().request("/tr/content/language-paylasilan")
    check(
        status == 200 and 'href="/content/language-shared"' in page,
        "The switcher missed the translation",
    )
    status, _, body = save_content(owner, "language-english", "tr")
    check(status == 303, f"Two languages could not share a slug: {body[:300]}")
    verify_editor(owner, shared, english, turkish, draft["id"])
    save(owner, {"code": "tr", "name": "Türkçe", "enabled": "0", "original_code": "tr"})
    status, headers, _ = Client().request("/tr/content/language-paylasilan")
    check(
        status == 302 and headers["location"] == "/content/language-shared",
        f"A disabled language did not lead to the default language's item: {status}",
    )
    status, _, body = owner.request(f"{PAGE}/tr/delete", "POST", {})
    check(status == 422, "A language that content uses was deleted")
    with FixtureStore.from_environment() as store:
        store.delete("items", [("slug", "like", "language-%")])
    status, _, body = owner.request(f"{PAGE}/tr/delete", "POST", {})
    check(status == 303, f"Deleting Turkish failed: {body[:200]}")
    print(
        "PASS Content is shown in its language, translated, and shared where untranslated",
        flush=True,
    )


def verify_editor(owner, shared, english, turkish, translation):
    languages = props(owner, f"/admin/content/{shared}/edit")["editor"]["languages"]
    check(
        [choice["code"] for choice in languages["choices"]] == ["en", "tr"]
        and [entry["language"] for entry in languages["translations"]] == ["tr"]
        and languages["missing"] == [],
        f"The editor did not list the item's translations: {languages}",
    )
    missing = props(owner, f"/admin/content/{english}/edit")["editor"]["languages"]["missing"]
    check([entry["code"] for entry in missing] == ["tr"], "The editor did not offer a translation")
    seeded = props(owner, missing[0]["url"])
    check(
        seeded["item"]["language"] == "tr"
        and seeded["item"]["title"] == "Language fixture language-english"
        and seeded["editor"]["languages"]["translationOf"] == english,
        "A new translation did not start as a copy of the item",
    )
    status, headers, _ = owner.request(f"/admin/content/new?translation_of={shared}&language=tr")
    check(
        status == 303 and headers["location"].endswith(f"/{translation}/edit"),
        "Translating into a language the item has opened a second translation",
    )
    listing = props(owner, "/admin/content?language=tr&q=Language%20fixture")
    check(
        {item["slug"] for item in listing["items"]}
        == {"language-turkce", "language-paylasilan", "language-english"},
        "The language filter of the content list was wrong",
    )
    check(
        "language" in [column["key"] for column in listing["columns"]],
        "The content list had no Language column",
    )
    public = Client()
    connection = issue(owner, "claude")
    succeeded(
        call(
            public,
            connection,
            "create_translation",
            {
                "collection": "entry",
                "id": turkish,
                "language": "en",
                "fields": {"title": "Language fixture in English", "slug": "language-turkish-en"},
            },
        )
    )
    found = succeeded(
        call(
            public, connection, "list_content_translations", {"collection": "entry", "id": turkish}
        )
    )
    check(
        [entry["language"] for entry in found["translations"]] == ["en"],
        f"MCP did not list the translation it created: {found}",
    )
    check(
        refused(
            call(
                public,
                connection,
                "create_translation",
                {"collection": "entry", "id": turkish, "language": "en"},
            )
        ),
        "MCP created a second translation in the same language",
    )
    print("PASS The editor, the content list and MCP manage translations", flush=True)


def verify_mcp(owner):
    public = Client()
    connection = issue(owner, "claude")
    names = tool_names(public, connection)
    expected = {
        "list_languages",
        "save_language",
        "reorder_languages",
        "set_default_language",
        "delete_language",
    }
    check(expected <= names, f"The language tools were not offered: {sorted(expected - names)}")
    listed = succeeded(call(public, connection, "list_languages", {}))["data"]["props"]
    check([item["code"] for item in listed["siteLanguages"]] == ["en"], "list_languages was wrong")
    succeeded(
        call(
            public,
            connection,
            "save_language",
            {"code": "ar", "name": "العربية", "direction": "rtl"},
        )
    )
    succeeded(call(public, connection, "save_language", {"code": "fr", "name": "Français"}))
    check(
        refused(call(public, connection, "save_language", {"code": "api", "name": "API"})),
        "MCP saved a language on a reserved address",
    )
    succeeded(call(public, connection, "reorder_languages", {"order": ["fr", "ar", "en"]}))
    check(codes(owner) == ["fr", "ar", "en"], "MCP did not reorder the languages")
    arabic = next(item for item in languages(owner) if item["code"] == "ar")
    check(arabic["direction"] == "rtl", "MCP lost the writing direction")
    succeeded(call(public, connection, "set_default_language", {"code": "fr"}))
    check(
        refused(call(public, connection, "delete_language", {"code": "fr"})),
        "MCP deleted the default language",
    )
    succeeded(call(public, connection, "set_default_language", {"code": "en"}))
    for code in ["fr", "ar"]:
        succeeded(call(public, connection, "delete_language", {"code": code}))
    check(codes(owner) == ["en"], "MCP left languages behind")
    print("PASS MCP lists, saves, orders, defaults and deletes languages", flush=True)


def run():
    email = os.environ["TEST_ADMIN_EMAIL"]
    password = os.environ["TEST_ADMIN_PASSWORD"]
    owner = login(email, password)
    verify_page(owner)
    verify_admin_language(owner, email, password)
    verify_routing(owner)
    verify_content(owner)
    verify_mcp(owner)


if __name__ == "__main__":
    run()
