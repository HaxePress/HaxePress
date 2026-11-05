# First installation

HaxePress is a development preview and is not production-ready. The first-run wizard follows the administration interface's typography, palette and field conventions.

`make setup` prepares project-local dependencies and creates a private `.env` with a random `APP_KEY`, `APP_INSTALLED=false` and an empty `INSTALL_TRUSTED_IPS`. It does not create or print an initial administrator password. Configure trusted literal IPv4/IPv6 socket-peer addresses explicitly, then build and start the site.

```dotenv
INSTALL_TRUSTED_IPS=127.0.0.1,::1
```

There is no wildcard or implicit loopback allowlist. Without an allowed address, the wizard returns a locked warning before creating a session or connecting to a fresh database. Client-submitted settings and forwarded identity headers cannot grant trust. Use a direct connection or an SSH tunnel for installation. The gate checks the actual peer address; it is not a generic reverse-proxy identity resolver.

The wizard is at `/admin/install`, so setup sessions keep the existing `/admin` cookie scope. Native session and CSRF middleware run only after the IP guard. Ordinary application routes, database migrations, plugins, scheduled jobs and MCP startup remain unavailable until installation completes. Static build assets still load so the locked screen is usable.

## Database

SQLite accepts a local `.sqlite` filename inside the configured storage disk, not an arbitrary filesystem path. MySQL accepts host, port, an existing empty database and credentials; the JVM runtime includes a pinned Connector/J driver. The native Schema API lists tables, then creates and drops a bounded probe table to verify DDL permissions. Nonempty databases are rejected rather than overwritten.

A successful check stores its configuration in the server-side setup session for ten minutes. Database passwords are never returned in page props or JSON summaries. The final step verifies the connection again; a browser-provided “verified” field has no effect.

The JVM MySQL compatibility patch uses the current JDBC driver name and finite connection/socket timeouts. JDBC uses column labels for aliases and normalizes numeric/timestamp values for native ORM casts. Native query identifiers are quoted for reserved names, MySQL text/JSON defaults use expression syntax, and foreign-key column types match unsigned auto-increment keys. SQL generation stays in framework compatibility patches; application and test code use native model/query builder and Schema APIs.

## Administrator and configuration

Choose a site name, administrator name/email and matching password of 12–72 bytes. Optional sample content is off by default. The native database initializer creates the schema and stores a password hash. Configuration output includes `APP_INSTALLED=true`, the selected database settings, site details and the requested initial administrator password.

The environment file is prepared with private visibility before initialization and atomically replaces `.env` after successful initialization. Other settings and comments are retained. Single-quoted values are literal, including `$`, `#`, quotes and backslashes, so credentials survive reload. The installer does not return these secrets to the browser or log credential values. The server-side database-check session record is removed on completion.

The first administrator is signed in with the explicit `admin` guard. Application services start without requiring a manual restart. On later requests and restarts the installation endpoints return 404. Changing `ADMIN_PASSWORD` afterward does not reset the database account; use account management for that.

If initialization fails, the main environment file is not replaced. Use an empty writable database before retrying; partial tables from a failed external database initialization may require operator cleanup. The wizard does not delete an existing database automatically.

## Existing installations

`APP_INSTALLED=true` preserves the ordinary application bootstrap. For installations predating that flag, an existing administrator record is detected through the native ORM and the installer remains closed. If an existing database cannot be verified, installation fails closed instead of treating an outage as a new site. Deployment backups retain `.env` and managed data.

## Verification

`tests/installation.py` launches isolated JVM/SSR applications and covers missing/wrong trusted IPs, forwarded-header rejection, no blocked sessions or database files, CSRF, path validation, native database/DDL checks, administrator creation, optional sample content, private `.env`, literal password reload, disabled setup and restart/login. A real isolated MySQL server can also be exercised through `verify_mysql`; its database is created/dropped with the test-only native Schema fixture.
