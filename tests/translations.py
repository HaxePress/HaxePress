"""Verify the Translations page: every text of the CMS and its packages, in every site language.

The CMS, themes and plugins ship their texts and translations; the page
lists them and the translations made on this site, which win over the
shipped ones. Removing the site's translation brings the shipped one back,
a language no package translates can be added, and the MCP tools do the
same through the page's routes.
"""

import json
import os
import re
import urllib.parse
from pathlib import Path

from admin_mcp import call, issue, refused, succeeded, tool_names
from cms_content import props
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore

ROOT = Path(__file__).resolve().parents[1]
PAGE = "/admin/translations"
NEWSLETTER = "plugin-newsletter"


def catalogue(path):
    return json.loads((ROOT / path).read_text())


def text_id(store, namespace, key):
    rows = store.scan("translation_texts", ["id", "key"], [("namespace", "=", namespace)])
    return next(row["id"] for row in rows if row["key"] == key)


def listed(client, **filters):
    return props(client, f"{PAGE}?{urllib.parse.urlencode(filters)}")


def save(client, text, language, expected=303, **values):
    data = {"text_id": str(text), "language": language, "return_to": PAGE, **values}
    status, _, body = client.request(f"{PAGE}/save", "POST", data)
    check(status == expected, f"Saving a translation returned {status}: {body[:300]}")
    return body


def home_title(client, path="/"):
    html = client.request(path)[2]
    match = re.search(r"<h1[^>]*>([^<]*)</h1>", html)
    return match.group(1).strip() if match else ""


def verify_sync(store):
    english = catalogue("resources/lang/en.json")
    turkish = catalogue("resources/lang/tr.json")
    count = store.count("translation_texts", [("namespace", "=", "cms")])
    check(count == len(english), f"The CMS listed {count} of {len(english)} texts")
    shipped = store.count(
        "translations",
        [("language", "=", "tr"), ("shipped", "!=", "")],
    )
    check(shipped >= len(turkish) - 5, f"Only {shipped} shipped Turkish translations were listed")
    audiences = {
        row["key"]: row["audience"]
        for row in store.scan(
            "translation_texts", ["id", "key", "audience"], [("namespace", "=", "cms")]
        )
    }
    check(audiences["The latest content"] == "site", "A public text was listed as admin-only")
    check(audiences["Manage languages"] == "admin", "An admin text was listed as public")
    plugin = catalogue("examples/plugins/newsletter/lang/en.json")
    listed_plugin = store.count("translation_texts", [("namespace", "=", NEWSLETTER)])
    check(
        listed_plugin >= len(plugin),
        f"The newsletter plugin listed {listed_plugin} of its {len(plugin)} catalogue texts",
    )
    print("PASS The CMS and its plugins list every text they ship and its audience", flush=True)


def verify_single_language(owner, store):
    page = listed(owner, source="core", q="The latest content")
    check(page["single"] and page["filter"]["language"] == "en", "The page was not in wording mode")
    item = next(item for item in page["items"] if item["key"] == "The latest content")
    check(item["status"] == "source", f"An English text had the status {item['status']}")
    public = Client()
    check(home_title(public) == "The latest content", "The homepage title changed unexpectedly")
    save(owner, item["id"], "en", value="Fresh from the notebook")
    check(
        home_title(Client()) == "Fresh from the notebook",
        "Changed wording was not shown on the site",
    )
    edited = listed(owner, source="core", status="edited")["items"]
    check([row["key"] for row in edited] == ["The latest content"], "The edited filter was wrong")
    status, _, _ = owner.request(
        f"{PAGE}/remove", "POST", {"text_id": str(item["id"]), "language": "en"}
    )
    check(status == 303, "Removing the changed wording failed")
    check(home_title(Client()) == "The latest content", "The source wording did not come back")
    print("PASS A single-language site changes any wording and restores it", flush=True)


def verify_new_language(owner, store):
    status, _, _ = owner.request(
        "/admin/languages/save",
        "POST",
        {"code": "de", "name": "Deutsch", "direction": "ltr", "enabled": "1", "home_page_id": "0"},
    )
    check(status == 303, "Adding German failed")
    page = listed(owner, language="de", source="core", status="missing")
    german = next(language for language in page["progress"] if language["code"] == "de")
    check(
        german["translated"] == 0 and german["total"] > 20,
        f"German started with translations: {german}",
    )
    check(
        all(item["status"] == "missing" for item in page["items"]),
        "The missing filter listed translated texts",
    )
    check(page["pagination"]["next"], "A long missing list had no next page")
    second = props(owner, page["pagination"]["next"])
    check(
        not {item["id"] for item in second["items"]} & {item["id"] for item in page["items"]},
        "Two pages of the missing list overlapped",
    )

    latest = text_id(store, "cms", "The latest content")
    save(owner, latest, "de", value="Das Neueste")
    check(home_title(Client(), "/de") == "Das Neueste", "A German translation was not shown")
    check(home_title(Client(), "/") == "The latest content", "German changed the default language")
    after = listed(owner, language="de", source="core", status="missing")["progress"]
    check(
        next(language for language in after if language["code"] == "de")["translated"] == 1,
        "Progress did not count the new translation",
    )
    edited = [item["id"] for item in listed(owner, language="de", status="edited")["items"]]
    check(edited == [latest], f"The edited filter listed other texts: {edited}")

    # Plural texts need both forms, and translations keep to the source's placeholders.
    plural = text_id(store, "cms", "Content count")
    save(owner, plural, "de", 303, one="{count} Inhalt", other="{count} Inhalte")
    detail = props(owner, f"{PAGE}/{plural}")
    german_detail = next(entry for entry in detail["entries"] if entry["language"] == "de")
    check(
        german_detail["translation"]["valueOne"] == "{count} Inhalt"
        and german_detail["translation"]["valueOther"] == "{count} Inhalte",
        "Plural forms were not saved",
    )
    status, _, body = owner.request(
        f"{PAGE}/save",
        "POST",
        {"text_id": str(plural), "language": "de", "one": "{anzahl} Inhalt", "other": "x"},
        extra_headers={"X-Well-Data": "true"},
    )
    check(status == 422 and "placeholders" in body, f"A wrong placeholder was accepted: {body}")
    status, _, body = owner.request(
        f"{PAGE}/save",
        "POST",
        {"text_id": str(plural), "language": "de", "value": "Inhalte"},
        extra_headers={"X-Well-Data": "true"},
    )
    check(status == 422, "A plural text was saved without its forms")
    status, _, body = owner.request(
        f"{PAGE}/save",
        "POST",
        {"text_id": str(latest), "language": "xx", "value": "Nope"},
        extra_headers={"X-Well-Data": "true"},
    )
    check(status == 422, "A translation into a language the site does not have was saved")
    print("PASS A new language lists missing texts, pages them and shows translations", flush=True)
    return latest


def verify_shipped(owner, store):
    subscribe = text_id(store, NEWSLETTER, "Subscribe")
    status, _, _ = owner.request(
        "/admin/languages/save",
        "POST",
        {"code": "tr", "name": "Türkçe", "direction": "ltr", "enabled": "1", "home_page_id": "0"},
    )
    check(status == 303, "Adding Turkish failed")
    translated = props(Client(), "/tr")["i18n"]["catalogues"][NEWSLETTER]
    check(translated["Subscribe"] == "Abone ol", "The plugin's shipped translation was not used")
    page = listed(owner, language="tr", source=NEWSLETTER, q="Subscribe")
    item = next(item for item in page["items"] if item["key"] == "Subscribe")
    check(
        item["status"] == "translated" and item["shipped"] == "Abone ol",
        f"A shipped translation was not listed: {item}",
    )
    save(owner, subscribe, "tr", value="Kaydol")
    translated = props(Client(), "/tr")["i18n"]["catalogues"][NEWSLETTER]
    check(
        translated["Subscribe"] == "Kaydol",
        "The site's translation did not replace the shipped one",
    )
    status, _, _ = owner.request(
        f"{PAGE}/save-batch",
        "POST",
        {"language": "tr", "remove": str(subscribe), "return_to": PAGE},
    )
    check(status == 303, "Removing a translation from the page failed")
    translated = props(Client(), "/tr")["i18n"]["catalogues"][NEWSLETTER]
    check(translated["Subscribe"] == "Abone ol", "The shipped translation did not come back")
    print("PASS The site's translations replace shipped ones until they are removed", flush=True)


def verify_page_form(owner, store, latest):
    page = listed(owner, language="de", source="core", q="Search")
    rows = page["items"][:2]
    data = {"language": "de", "ids": page["ids"], "return_to": PAGE}
    for row in page["items"]:
        data[f"original_{row['id']}"] = row["value"]
        data[f"value_{row['id']}"] = row["value"]
    for row in rows:
        data[f"value_{row['id']}"] = f"Suche {row['id']}"
    status, headers, _ = owner.request(f"{PAGE}/save-batch", "POST", data)
    check(status == 303 and "notice=saved" in headers["location"], "Saving a page failed")
    saved = {
        item["id"]: item["value"]
        for item in listed(owner, language="de", source="core", status="edited")["items"]
    }
    check(
        all(saved.get(row["id"]) == f"Suche {row['id']}" for row in rows),
        "The page's changed rows were not saved",
    )
    expected = {latest, *[row["id"] for row in rows]}
    check(
        set(saved) == expected,
        f"Unchanged rows were saved as translations: {sorted(saved.values())}",
    )
    print("PASS The page saves the rows that changed and only those", flush=True)


def verify_islands(owner, store):
    before = Client().request("/de")[2]
    match = re.search(r"/_translations/de-[0-9a-f]{12}\.json", before)
    if match is None:
        print("PASS Island catalogues are not used on this page", flush=True)
        return
    save(owner, text_id(store, "cms", "Search"), "de", value="Suchen")
    after = Client().request("/de")[2]
    changed = re.search(r"/_translations/de-[0-9a-f]{12}\.json", after)
    check(changed and changed.group(0) != match.group(0), "The island catalogue kept its address")
    body = Client().request(changed.group(0))[2]
    check(json.loads(body)["Search"] == "Suchen", "The island catalogue lacked the translation")
    print("PASS Island catalogues follow the site's translations", flush=True)


def verify_mcp(owner, store, latest):
    public = Client()
    connection = issue(owner, "claude")
    names = tool_names(public, connection)
    expected = {
        "list_translation_sources",
        "get_translation_progress",
        "list_translations",
        "get_translation",
        "save_translation",
        "save_translations",
        "remove_translation",
        "export_translations",
        "import_translations",
        "rescan_translations",
    }
    check(expected <= names, f"Translation tools were missing: {sorted(expected - names)}")
    sources = succeeded(call(public, connection, "list_translation_sources", {}))["data"]
    check(
        {"core", "site", NEWSLETTER} <= {item["source"] for item in sources["sources"]},
        "list_translation_sources left a source out",
    )
    progress = succeeded(
        call(public, connection, "get_translation_progress", {"source": NEWSLETTER})
    )["data"]
    german = next(item for item in progress["languages"] if item["code"] == "de")
    check(
        german["translated"] == 0 and german["missing"] > 5, f"Plugin progress was wrong: {german}"
    )
    missing = succeeded(
        call(
            public,
            connection,
            "list_translations",
            {"language": "de", "source": NEWSLETTER, "status": "missing"},
        )
    )["data"]["props"]["items"]
    items = [
        {"id": item["id"], "value": f"DE {item['key']}"}
        for item in missing[:5]
        if not item["plural"]
    ]
    items.append({"id": missing[0]["id"], "value": "Bad {placeholder}"})
    result = succeeded(
        call(public, connection, "save_translations", {"language": "de", "items": items})
    )["data"]
    check(
        len(result["saved"]) == len(items) - 1 and len(result["failed"]) == 1,
        f"A batch did not save the valid items and report the invalid one: {result}",
    )
    detail = succeeded(call(public, connection, "get_translation", {"id": items[0]["id"]}))["data"]
    german_entry = next(entry for entry in detail["props"]["entries"] if entry["language"] == "de")
    check(german_entry["translation"]["value"] == items[0]["value"], "get_translation was wrong")
    check(
        refused(
            call(
                public,
                connection,
                "save_translation",
                {"id": latest, "language": "de", "value": "{wrong}"},
            )
        ),
        "MCP saved a translation with an unknown placeholder",
    )
    succeeded(
        call(public, connection, "remove_translation", {"id": items[0]["id"], "language": "de"})
    )
    exported = succeeded(
        call(
            public,
            connection,
            "export_translations",
            {"source": NEWSLETTER, "language": "de", "include": "missing"},
        )
    )["data"]
    check(exported["complete"] and exported["messages"], "Exporting missing texts returned nothing")
    messages = {
        key: f"Import {index}"
        for index, key in enumerate(exported["messages"])
        if isinstance(exported["messages"][key], str)
    }
    messages["Not a key of this plugin"] = "Unknown"
    imported = succeeded(
        call(
            public,
            connection,
            "import_translations",
            {"source": NEWSLETTER, "language": "de", "messages": messages},
        )
    )["data"]
    check(
        imported["imported"] == len(messages) - 1 and imported["unknownCount"] == 1,
        f"Importing a catalogue was wrong: {imported}",
    )
    again = succeeded(
        call(
            public,
            connection,
            "import_translations",
            {"source": NEWSLETTER, "language": "de", "messages": messages},
        )
    )["data"]
    check(again["imported"] == 0, "Importing missing texts twice overwrote translations")
    succeeded(call(public, connection, "rescan_translations", {}))
    check(
        store.count("translation_texts", [("namespace", "=", "cms")])
        == len(catalogue("resources/lang/en.json")),
        "Rescanning changed the CMS texts",
    )
    print("PASS MCP lists, saves, removes, exports and imports translations", flush=True)


def verify_site_texts(owner, store):
    """The site's name, menu labels and categories are texts of the Translations page."""
    site_name = text_id(store, "site", "setting.site_name")
    save(owner, site_name, "de", value="Deutsche Seite")
    check("Deutsche Seite" in Client().request("/de")[2], "The site name was not translated")
    check("Deutsche Seite" not in Client().request("/")[2], "The translation changed English")
    menu = store.rows(
        "menu_links", ["id", "label"], [("location", "=", "header"), ("label", "=", "Content")]
    )[0]
    label = text_id(store, "site", f"menu.{menu['id']}.label")
    save(owner, label, "de", value="Beiträge")
    check("Beiträge" in Client().request("/de")[2], "A menu label was not translated")
    status, _, _ = owner.request("/admin/categories/save", "POST", {"name": "Gardening"})
    check(status == 303, "Creating a category failed")
    category = store.rows("categories", ["id"], [("name", "=", "Gardening")])[0]["id"]
    item = text_id(store, "site", f"category.{category}.name")
    save(owner, item, "de", value="Gartenarbeit")
    status, _, _ = owner.request(
        "/admin/categories/save", "POST", {"id": str(category), "name": "Garden work"}
    )
    check(status == 303, "Renaming a category failed")
    review = listed(owner, language="de", source="site", status="review")["items"]
    check(
        [row["key"] for row in review] == [f"category.{category}.name"],
        f"A renamed category's translation was not marked for review: {review}",
    )
    owner.request(f"/admin/categories/{category}/delete", "POST", {})
    check(
        store.count("translation_texts", [("key", "=", f"category.{category}.name")]) == 0,
        "A deleted category left its text behind",
    )
    status, _, body = owner.request(
        f"{PAGE}/save",
        "POST",
        {"text_id": str(site_name), "language": "en", "value": "Changed here"},
        extra_headers={"X-Well-Data": "true"},
    )
    check(
        status == 422 and "/admin/settings" in body,
        "A site text was changed in its own language from the Translations page",
    )
    print("PASS The site's name, menus and categories are translated per language", flush=True)


def verify_access(owner):
    email = "translations-writer@example.test"
    password = "Translations-writer-1"
    member = {"name": "Writer", "email": email, "role": "writer", "password": password}
    status, _, _ = owner.request("/admin/team/save", "POST", {**member, "active": "1"})
    check(status == 303, "Could not create a writer")
    writer = login(email, password)
    status, _, _ = writer.request(PAGE)
    check(status == 403, f"A writer opened the Translations page: {status}")
    print("PASS Only members who manage translations open the page", flush=True)


def cleanup(owner):
    for code in ["tr", "de"]:
        owner.request(f"/admin/languages/{code}/delete", "POST", {})
    with FixtureStore.from_environment() as store:
        store.delete("translations", [("value", "!=", "")])


def run():
    owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    with FixtureStore.from_environment() as store:
        try:
            verify_sync(store)
            verify_single_language(owner, store)
            latest = verify_new_language(owner, store)
            verify_shipped(owner, store)
            verify_page_form(owner, store, latest)
            verify_islands(owner, store)
            verify_site_texts(owner, store)
            verify_mcp(owner, store, latest)
            verify_access(owner)
        finally:
            cleanup(owner)


if __name__ == "__main__":
    run()
