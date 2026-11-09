# Languages

A HaxePress site publishes in one language until you add more on **Administration → Languages**. A site with one language has no language prefixes, no language switcher, no `hreflang` links and no Language column. Nothing about it changes when a second language is added later: its addresses stay where they are.

## Site languages

Each language has a code, a name written in the language itself, a writing direction, a position and an optional homepage. Codes are BCP 47 subsets: a two- or three-letter language, an optional script and an optional region, such as `en`, `de`, `pt-BR` or `zh-Hant-TW`. A site can have up to 32 languages.

- **Default language.** Exactly one language is the default. Its pages have no prefix; every other language is served under its code in lowercase, such as `/de/` or `/pt-br/`. Making another language the default moves the addresses: its pages lose their prefix and the former default moves under its code. A request for the default language's prefix, such as `/en/about`, is redirected permanently to `/about`.
- **Disabled languages.** A language can be disabled. Its content and translations stay, and the administration keeps editing and previewing it, so a language can be prepared before it goes public. Visitors never see it: it is not in the switcher or in `hreflang` links, and its items are not shown in other languages. A request for its address is redirected (302, because the language may come back) to the same content in the default language, or to the homepage.
- **Reserved addresses.** A language code cannot be an address the site already uses, such as `api`, a collection's public path or a path kept as a redirect, and a collection cannot take a language's code as its path. Administration, media, assets and API paths (`hx.press.SitePaths`) are never served under a prefix.
- **Deleting.** A language that content or a navigation link uses cannot be deleted. The default language cannot be deleted or disabled.

New sites start with `SITE_LANGUAGE` from `.env`, or English.

## Content

Each translation is its own content item with its own language, slug, status and revisions. Items that translate each other share a translation group, which an item gets with its first translation.

- **One language.** An item is shown only in its language.
- **Translations.** **Translate into …** in the editor starts a draft in another language as a copy of the item, with its tags and custom fields. A group holds one item per language. A slug is unique within a collection and language, so translations can keep the same slug or use their own.
- **Shown in every language.** An item marked **Show in every language** is also listed in the languages its group has no *published* item in. It appears there at that language's address (`/de/blog/hello`) in its own language, with its canonical link pointing at its own address. Once a translation is published, the translation takes its place; a draft does not. An item is never listed twice in one language, and a group has at most one item marked this way.

A visitor who opens the address of a translated item in another language, such as `/de/blog/hello` after the German translation was published as `/de/blog/hallo`, is redirected there. Featured items are chosen per collection and language. The homepage of a language is the content its language names, else the translation of the site's homepage content, else that content.

Lists, counts, feeds, related items and theme feeds read `hx.press.content.ContentTranslations.visibleIn` in SQL, and every cached result includes the page's language. The admin content list has a Language column and filter on multilingual sites.

## Addresses and links

`hx.press.i18n.LanguageRouting` runs before routes are resolved (HxWell's `Route.rewrite`, `patches/hxwell-request-rewrite.patch`), so core and plugin routes such as `/de/rss.xml` work under every prefix without a second registration.

Templates write links without a prefix, such as `/about`; the page's language is added when it renders. A link into another language uses `Languages.explicitPath(code, path)`, which pages keep as written; a link into the default language loses its prefix. Props for islands carry final addresses, such as `item.url`.

## Search engines

Public pages render `<SiteHead />` (in `Document`): the canonical address, `og:url` and `og:locale`. On a site with more than one public language they also link every language of the page with `hreflang`, plus `x-default` for the default language: a content page links its published translations; the homepage, archives and other pages link every language; filtered and paged lists link none. Themes with their own document layout should include `<SiteHead />` in their head.

## Administration language

Each member chooses the administration's language for themselves; it is stored on their account (`admins.ui_language`) and is independent of the site's languages. The sign-in page uses the browser's language until a member chooses one there. The choices are the languages the CMS has catalogues for and the site's languages; administration texts without a translation are shown in English.

## Plugins

- `ContentViews.language(request)` is the language of a public page, and `Languages` lists the site's languages and builds addresses.
- `ContentTranslations.visibleIn(query, kind, language)` limits a content query to what visitors read in a language.
- `SiteTexts.settings(map)` returns the site settings in the page's language.

The RSS feed is per language, and its channel has a `<language>`.

## MCP

`list_languages`, `save_language`, `reorder_languages`, `set_default_language` and `delete_language` manage languages. Content tools take `language`, `showInAllLanguages`, `translationOf` and `detachTranslation`; `create_translation` starts a translation as a copy, `list_content_translations` lists an item's translations, and `list_content` filters by `language`. `save_navigation_link` takes `language` for a link shown in one language.
