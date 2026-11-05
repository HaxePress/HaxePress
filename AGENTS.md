# Project coding conventions

## Imports

- For Haxe types from another package, add an explicit import and use their short names in calls, constructors, type annotations, generics, and class references.
- Use `import hx.well.facades.Inertia;` followed by `Inertia.resolveUrlUsing(...)`. Do not write `hx.well.facades.Inertia.resolveUrlUsing(...)` in executable code.
- This applies even when a type is used only once.
- Resolve type-name collisions with an import alias rather than an inline fully qualified name.
- Keep intentional static-helper imports, including `import hx.well.http.RequestStatic.auth;` and explicit `auth("admin")` calls.
- Package declarations, `import`/`using` declarations, and required runtime binding strings such as `@:native("javax.imageio.ImageIO")` retain their qualified names.
- Apply this convention to repository-owned source and code maintained in project compatibility patches. Generated output and unmodified third-party dependencies are outside its scope.

Compile the JVM target after changing imports to verify type and native-binding resolution.

## File access

- Use `hx.well.facades.Storage` and configured disks for application, plugin and Haxe test file operations. Prefer native `put`, `writeStream`, `readStream`, `response` and `download` methods over direct `File`, `FileSystem` or Java filesystem calls.
- Keep managed paths relative to their disk. Resolve physical paths with `StorageDisk.path()` only at native runtime boundaries such as JVM class loading and archive inspection.
- Keep bounded streaming for ZIP extraction and exports. The caller closes streams supplied to `writeStream`; temporary export cleanup must also run after a response disconnects.

## Readability and HxWell APIs

- Use descriptive intermediate variables for filtering, mapping, validation, and page props. Prepare data before calling `Inertia.render`.
- Keep one statement per line and use multiline blocks. Do not hand-minify Haxe, JSX, CSS, or Python source.
- Prefer the installed framework's APIs: `request.validate`, `request.only`, model queries, `toObject`, and `Inertia.render(component, props)`. Check their implementation before creating a wrapper or assuming Laravel API parity.
- In this adapter, `withData` is for root-template data, not page props. Prepare all page props before calling `Inertia.render`.
- Cache typed data records from the models' native `toObject()` output. Model instances depend on constructor-initialized ORM metadata that this cache backend does not restore. Add presentation fields only when preparing page props.
- The notes sample uses an older `Note.instance` API; this project's installed version uses `Model.query`. Keep explicit `auth("admin")` calls.
- Use the standard formatter for each language and run `npm run format:check` before finishing source changes.

## Query scope and caching

- Application and test source must use model/query builder and Schema APIs, without raw SQL strings, `selectRaw`, `whereRaw`, or direct database statements. Test data uses the test-only JVM ORM fixture process. Maintain necessary framework compatibility changes in `patches/hxwell-query-builder.patch`, rather than introducing SQL wrappers. Connection/result-set decorators may observe and forward framework-generated statements; they must not construct or rewrite them.
- Filter, count, sort, and limit collections in SQL. Never load a full table or a whole-entity cache and filter it for a page or detail request.
- Select only the columns used by the response. Content bodies belong to a single detail/editor query or a SQL search predicate, not list projections.
- Cache a specific query result: include filters, cursor, page size, and lookup identifiers in its key. Keep aggregate counts separate from result rows.
- Use bounded cursor pagination for lists and batches/streams for exports or migrations. Presentation mapping may run only on those bounded results.
- Keep reading time as write-time metadata so lists do not need to fetch content bodies.
