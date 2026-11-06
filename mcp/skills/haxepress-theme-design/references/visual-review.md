# Reviewing a design in the preview

Read this before you call a design finished, and whenever a person says
something "looks off". `preview_theme_design` (`preview_theme` on a theme
connection) renders a real page of the site with the theme's saved draft in a
browser and returns a screenshot plus the page's HTTP `status`, `title`,
`pageHeight`, `headings` and internal `links`.

```json
{ "themeId": "theme-harbor", "path": "/", "device": "mobile", "fullPage": true }
```

- `device`: `desktop` (1280×800), `tablet` (834×1112) or `mobile` (390×844).
- `fullPage: true` captures up to 8,000 pixels of the page; use it for the
  homepage and long articles, and the first screen for everything else.
- `design: "published"` shows what visitors see today, useful as a "before"
  picture. The default `draft` shows your saved work. Unsaved operations are
  never visible, so save before you look.

## The route through the site

The preview only knows the pages the site really has, so walk it through
links instead of guessing URLs:

1. `/` on desktop, full page. Read `links` from the result.
2. Follow a collection archive link (often `/content` or the collection's
   public path) and an item inside it.
3. `/about`, a static page if the menu has one, and a missing page such as
   `/no-such-page` (it should return status 404 and still look designed).
4. Repeat the homepage, archive and item on `mobile`, and the homepage on
   `tablet`.

A status other than 200 (or 404 for the missing page) means the page is broken
or the path does not exist; check `links` for the real path.

## What to look for

Look at each screenshot as a visitor would, then check the specifics.

**Layout**

- Nothing runs off the right edge on mobile; no horizontal scroll. Grids
  collapse to one column at 390px. Images keep their proportions.
- Spacing has a rhythm: related things close together, sections clearly
  apart. Nothing is cramped against the screen edge on mobile.
- The first screen of the homepage says what the site is within a glance.

**Type**

- Body text is at least 16px on mobile and lines are not wider than about 75
  characters on desktop.
- Headings step down in size; `headings` in the result should start with one
  `h1` per page and not skip levels.
- Long real titles wrap cleanly instead of overflowing.

**Color and contrast**

- Body text against its background meets 4.5:1, headings and buttons 3:1.
  Light gray text on white and white text on a light photo are the usual
  failures.
- Links and buttons are recognizable, and the accent is used sparingly.

**Content**

- No placeholder text left from presets ("Your heading", "Add your text
  here.", "Learn more" pointing at `/`).
- Repeaters show real items. If a list is empty, the collection may have no
  published content; say so instead of hiding the section.
- Cards without images still look intended (use a `condition`).
- The header shows the site's brand and menu; the footer is not an
  afterthought.

## Fixing and checking again

Fix the largest problem first, save, and preview the same page and device
again to confirm it. Then re-check one other device, because a mobile fix
often changes desktop. Stop when every page in the route looks intentional;
mention anything you could not fix in your hand-over.
