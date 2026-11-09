package hx.press.config;

import hx.well.config.FilesystemsConfig;
import hx.well.facades.Environment;
import hx.well.facades.Config;
import hx.well.handler.PublicHandler;

class StorageConfig extends FilesystemsConfig {
    public function new() {
        super();
        PublicHandler.contentType.set("gif", "image/gif");
        PublicHandler.contentType.set("mjs", "text/javascript");
        default_disk = "local";
        // Everything the web server must not serve lives under private/; public/ is the web root.
        var storage = Environment.env("STORAGE_PATH", "private/storage");
        disks = [
            "configuration" => {
                driver: "local",
                root: ".",
                visibility: "private",
                throw_errors: true
            },
            "local" => {
                driver: "local",
                root: storage,
                visibility: "private",
                throw_errors: true
            },
            // SQLite databases the installer creates live here, apart from the files in storage.
            "data" => {
                driver: "local",
                root: Environment.env("DATA_PATH", "private/database"),
                visibility: "private",
                throw_errors: true
            },
            "media" => {
                driver: "local",
                root: '${storage}/media',
                url: "/media",
                visibility: "private",
                throw_errors: true
            },
            "theme_assets" => {
                driver: "scoped",
                disk: "local",
                prefix: "themes",
                throw_errors: true
            },
            "image_uploads" => {
                driver: "scoped",
                disk: "local",
                prefix: "image-uploads",
                throw_errors: true
            },
            "extensions" => {
                driver: "scoped",
                disk: "local",
                prefix: "extensions",
                throw_errors: true
            },
            "exports" => {
                driver: "scoped",
                disk: "local",
                prefix: "exports",
                throw_errors: true
            },
            // The plugin and theme archives shipped with the application, outside the web root.
            "bundled" => {
                driver: "local",
                root: Environment.env("PACKAGES_PATH", "private/packages"),
                read_only: true,
                throw_errors: true
            },
            "public" => {
                driver: "local",
                root: Environment.env("PUBLIC_PATH", "public"),
                read_only: true,
                throw_errors: true
            },
            "seeds" => {
                driver: "local",
                root: "private/seeds",
                read_only: true,
                throw_errors: true
            }
        ];
        Config.set("filesystems", this);
    }
}
