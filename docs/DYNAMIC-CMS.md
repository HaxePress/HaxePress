# Definition-driven CMS architecture

The application has been reviewed across content storage, queries, routing, permissions, editor workflows, navigation, themes, native plugins, translations and media. Its business data must not depend on a fixed entry/page split. Existing content, credentials, uploaded files, working copies and package state must survive.

## Architecture boundaries

| Area | Definition source | Execution boundary |
| --- | --- | --- |
| Collections | Stored content type key, labels, features, constraints and paths | Shared guarded collection routes, controllers and workflow |
| Custom fields | Typed field definitions on the collection | Native validation, scoped values, projections and query-builder predicates |
| Lists | Core metadata plus explicitly listed scalar fields | Cursor pages; specific query caches; bounded SQL projections |
| Public addresses | Collection definitions and retained old paths | Native routes take precedence; the public handler resolves stored paths at request time |
| Rendering | Named detail/archive/home templates | Partial theme implementations with standard CMS fallback views |
| Plugin data | Stable owner identifiers and native model/Schema APIs | Creation/destruction lifecycle; inactive owners retain stored data |
| Navigation | Route metadata, content definitions and managed menus | Server-filtered administration navigation and public navigation regions |
| Roles | Capability grants | Request-time checks and explicit administrator sessions |
| Media | Storage disks and shared reference/upload policy | Bounded uploads, streamed responses and referenced-file protection |

Core resource limits, authentication/session checks, CSRF, Storage path containment and allowed scalar representations remain server-enforced invariants. Content definitions configure the CMS; trusted native plugins provide additional executable behavior.

## Verified acceptance scenarios

- A site owner creates a Products collection, adds scalar/select/date/boolean/image fields, chooses public/list/filter visibility and immediately uses its editor and public addresses without a server restart.
- Different collections can use the same slug. Renaming a collection's public path preserves old URLs as redirects. Conflicting paths are rejected.
- Private collections/fields do not appear in public responses or permit public filtering/inference. Writers remain limited to their own content.
- Custom values survive manual saves, ordered working copies, history snapshots, restoration, trash/restore and process restarts. Images used by custom fields remain protected from deletion.
- Lists select only base metadata and explicitly listed scalar values. Private values are excluded from public projections. Filters use bound native membership subqueries; no whole-table ID lists or raw application SQL are introduced.
- Native plugins register owned definitions, retain site customizations, and stop exposing their collections when disabled, failed or uninstalled. Their data remains available after reinstall.
- Partial/custom themes use declared names and arbitrary valid layout identifiers. Administration templates remain separate. Unknown public templates fall back to the standard view.
- Theme previews support the same collection addresses and filters inside the isolated frame.
- Existing installation comparisons verify preserved original records and file hashes through the ORM fixture process and Storage/native backup tools.

## Verification evidence

- `outputs/dynamic-full-test.log`: the complete fresh-install JVM suite, including existing CMS flows, query/cache guards, multi-batch migrations, restart persistence, package lifecycle, translations and native shutdown.
- `outputs/dynamic-final-structure-test.log`: runtime collections/fields, public/private/list/filter boundaries, zero/false handling, required fields, revision/working-copy values, managed image references, path redirects, role ceilings and live session permission changes. Additional presentation checks cover partial/named templates, ordinary fallback views, custom navigation regions, generic content links, preview frames, content-backed homepages and independent site/account identity.
- `outputs/dynamic-final-cppia.log` / `outputs/dynamic-final-php.log`: native CMS definition registration, field/ORM projections, scoped role grants, ownership availability, stored customization retention, plugin persistence/lifecycle and archive handling on real C++/CPPIA and PHP hosts.
- `outputs/dynamic-browser.json` and `outputs/dynamic-interactive-browser.json`: 24 screen checks plus an interactive collection/field/content creation flow, desktop/mobile layouts, native keyboard/modal behavior, translations, public style separation and no browser console errors.
- `outputs/dynamic-upgrade-verification.json`: an actual CMS 2.0 database/media copy upgraded to 2.1 / API 4. Original ORM record hashes and media checksums match after the intended menu-reference naming change. Repeated startup passes.
- `outputs/dynamic-final-format-check.log`: Haxe, Prettier and Black checks. Framework compatibility patches reverse/reapply exactly. Source scans find no raw application/test SQL, direct Haxe filesystem calls or inline qualified type references.

The bundled Content/Page, Category/Tag and Header/Footer definitions remain useful defaults. The shared content/workflow/query layer accepts arbitrary registered collection keys; stored declarations control their features and roles. Scalar types and the safe publishing/authentication/Storage boundaries remain kernel policies rather than executable database configuration.

## Release boundary

CMS 2.1.0 uses native plugin/theme API 4. The native ORM/export graph changed, and detail/page templates share the `item` contract. Native packages must be rebuilt against this exact release and its compatibility patches. Matching bundled upgrades retain package settings, activation, selected theme and stored data.


Local deployment backups are stored under the ignored `storage/backups/` directory. Live preservation results are recorded in `outputs/dynamic-live-verification.json`; production build and package logs use the `dynamic-production-*` prefix.

The running local JVM also passes existing-credential login, dynamic collection/schema/role/menu screens, session-free public content, RSS and legacy links. Evidence: `outputs/dynamic-live-smoke.json`. Original record/file comparisons are in `outputs/dynamic-live-verification.json`.
