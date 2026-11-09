# Translations

**Organization → Translations** lists every text visitors and members read: the texts of HaxePress, of each theme and plugin, and of the site itself, such as its name, menu labels and category names. For each site language it shows what the page shows and lets you translate it.

- A theme or plugin ships its texts and the translations it has. They are listed as they are.
- A translation made on the site replaces the one the package ships. **Use the shipped translation** removes it again.
- A language no package translates can still be translated here: every text is listed as missing until it has a translation.
- On a site with one language the page lists the same texts in that language, so any wording can be changed.

Updates of a theme or plugin change only what it ships. The site's translations are kept; a text whose source wording changed is marked **Needs review**, and a text a package no longer ships stays as **No longer used** while the site has a translation of it.

## Model

`translation_texts` holds one row per text: its namespace (`cms`, a package id, or `site`), key, source wording, the language of that wording, whether it is plural (`{"one", "other"}` as JSON), its origin (`catalogue`, `template`, `manifest`, `setting`, `menu`, `category`, `tag`…) and whether visitors (`site`) or members (`admin`) read it. Keys are matched by their MD5 (`TextKeys.hash`).

`translations` holds one row per text and language: `value`, the site's translation, and `shipped`, a copy of the package's translation. A text with neither in a language has no row there: it is missing.

The shipped catalogue files stay the source of truth at runtime. `I18n` merges, once per revision of the translations and for each namespace and language: English, the source catalogue, the site's changes to the source wording, the catalogue of the language (or its base language, such as `pt` for `pt-BR`) and the site's translations into it. Pages read these merged maps and never query single texts. Island catalogues (`/_translations/{language}-{hash}.json`) include the site's translations, and their address changes when they do.

## Where texts come from

- **HaxePress.** The core catalogue (`resources/lang/{code}.json`) once for each build. Keys used by public templates, or by the templates of installed themes, are site texts; the others belong to the administration and are hidden unless **Shown in** includes it.
- **Themes and plugins.** On every install and update: the package's catalogues, the labels of its manifest, and the literal keys of `t(key)` and `translate(namespace, key)` in its templates, also those its catalogues leave out. Keys of the core catalogue stay CMS texts. A package names the language of its own texts with `sourceLanguage` in its manifest (English by default). Uninstalling removes its texts and their translations.
- **The site.** The site name, description, about text and publisher, menu labels, category names and tag names. Their source wording is edited where they are, such as the Settings page; the Translations page translates it into the other languages. A wording that is also a CMS text, such as a seeded "Home" menu label, gets the CMS translations as its shipped ones.

**List texts again** reads every source again after files changed outside the administration.

## Checks

A translation keeps to the placeholders of its source: a `{name}` the source does not have is refused, and one it leaves out is reported. Plural texts need both forms. Translations are at most 4000 characters.

## Access

Members with the **Manage translations** capability open the page; owners and editors have it. **List texts again** also needs **Manage themes and plugins**.

## MCP

`list_translation_sources`, `get_translation_progress`, `list_translations` (by language, source, status and search, 50 per page), `get_translation`, `save_translation`, `save_translations` (up to 100; valid items are saved and invalid ones reported), `remove_translation`, `export_translations` and `import_translations` (a catalogue of key to text, filling only missing texts unless `overwrite`) and `rescan_translations` work like the page. Downloading a whole file is people-only.
