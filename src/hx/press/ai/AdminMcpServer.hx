package hx.press.ai;

import haxe.Exception;
import haxe.Json;
import haxe.Int64;
import haxe.crypto.Sha256;
import hx.press.CmsVersion;
import hx.press.access.Roles;
import hx.press.ai.AdminMcpAccess.AdminMcpGrant;
import hx.press.ai.AdminMcpBridge.AdminReply;
import hx.press.mcp.McpMediaInput;
import hx.press.mcp.McpSchema;
import hx.press.mcp.McpSchema.McpField;
import hx.press.mcp.McpSchema.field;
import hx.press.mcp.McpSchema.optional;
import hx.press.mcp.McpServer;
import hx.press.mcp.McpSkills;
import hx.press.mcp.McpTools;
import hx.press.themes.ThemeMcpTools;

/**
    The admin MCP catalog of one account: named tools for content,
    taxonomy, media, navigation, extensions, themes, settings and the
    account, the plugin tools its role may use, and generic access to the
    other permitted admin routes. The catalog follows the account's current
    role; every tool calls a native admin route in-process.
**/
class AdminMcpServer {
    static inline var MAX_ID = 2147483647;
    static final kindPattern = "^[a-z][a-z0-9_]{0,31}$";
    static final keyPattern = "^[a-z][a-z0-9_-]{0,79}$";

    final server:McpServer;
    final bridge:AdminMcpBridge;
    final grants:Array<String>;

    function new(server:McpServer, grant:AdminMcpGrant) {
        this.server = server;
        this.bridge = new AdminMcpBridge(grant);
        this.grants = Roles.grants(grant.admin.role);
    }

    public static function create(grant:AdminMcpGrant):McpServer {
        var server = new McpServer("haxepress-admin", CmsVersion.version);
        var catalog = new AdminMcpServer(server, grant);
        server.instructions = catalog.instructions();
        catalog.registerAll();
        return server;
    }

    function can(capability:String):Bool {
        return grants.contains("*") || grants.contains(capability);
    }

    function instructions():String {
        var lines = [
            "Use the named CMS tools. Read the saved version before editing content or a theme.",
            "For articles, upload_media_image stages original bytes or an attachment. Inspect the returned image and confirm its hash and dimensions with verify_media_image, then use set_content_cover or insert_content_image.",
            "For themes, start with list_themes and inspect_theme_tree. Use upload_theme_image, verify_theme_image and set_theme_block_image for theme-owned images."
        ];
        if (can("extensions")) {
            lines.push(McpSkills.pointer);
        }
        if (can("translations")) {
            lines.push(AdminMcpTranslationTools.instruction);
        }
        return lines.join(" ");
    }

    static function id():Dynamic {
        return McpSchema.integer(1, MAX_ID);
    }

    static function key():Dynamic {
        return McpSchema.string(null, null, keyPattern);
    }

    static function name():Dynamic {
        return McpSchema.string(100, 1);
    }

    static function kind():Dynamic {
        return McpSchema.describe(McpSchema.string(null, null, kindPattern),
            "Collection key, such as entry for articles, page for pages, or a custom collection key.");
    }

    /** Zod trims names before it checks them; empty names are refused after trimming. **/
    static function trimmed(value:String):String {
        var text = StringTools.trim(value);
        if (text == "") {
            throw new Exception("Input validation error: name: Too small: expected string to have >=1 characters");
        }
        return text;
    }

    /** A number as JavaScript's `String()` writes a whole number: digits without an exponent. **/
    public static function numberText(value:Dynamic):String {
        if (value == null) {
            return "0";
        }
        if (Std.isOfType(value, Int)) {
            return '${value}';
        }
        var amount:Float = value;
        if (Math.ffloor(amount) == amount && Math.abs(amount) < 9007199254740992.0) {
            return Int64.toStr(Int64.fromFloat(amount));
        }
        return '${amount}';
    }

    function add(name:String, description:String, fields:Array<McpField>, isReadOnly:Bool,
            run:Dynamic->Dynamic, ?meta:Dynamic):Void {
        McpTools.add(server, name, description, fields, isReadOnly, run, meta);
    }

    /** The `id` argument as text, or an empty string when it is absent. **/
    static function optionalId(value:Null<Int>):String {
        return value == null ? "" : '${value}';
    }

    static function identifier(arguments:Dynamic):Int {
        var id:Int = arguments.id;
        return id;
    }

    function call(path:String, method:String = "GET", ?data:Dynamic):Dynamic {
        return AdminMcpBridge.result(bridge.request(path, method, data));
    }

    static function browsePath(path:String, arguments:Dynamic):String {
        var parameters:Array<String> = [];
        if (arguments.q != null && arguments.q != "") {
            parameters.push('q=${StringTools.urlEncode(arguments.q)}');
        }
        if (arguments.cursor != null && arguments.cursor != "") {
            parameters.push('cursor=${StringTools.urlEncode(arguments.cursor)}');
        }
        return parameters.length == 0 ? path : '${path}?${parameters.join("&")}';
    }

    function registerAll():Void {
        registerGeneric();
        registerLists();
        new AdminMcpContentTools(server, bridge, can("media"), can("publish")).register();
        if (can("taxonomy")) {
            registerTaxonomy();
        }
        if (can("media")) {
            registerMedia();
        }
        if (can("navigation")) {
            registerNavigation();
        }
        if (can("extensions")) {
            registerExtensions();
        }
        if (can("settings")) {
            registerSettings();
        }
        if (can("translations")) {
            new AdminMcpTranslationTools(server, bridge, can("extensions")).register();
        }
        add("update_account_name", "Change the display name of your current admin account.",
            [field("name", name())], false, arguments -> call("/admin/account", "POST", {
                name: trimmed(arguments.name)
            }));
        registerPluginTools();
    }

    function registerGeneric():Void {
        var path = McpSchema.string(1024, null, "^\\/admin.*");
        path.format = "starts_with";
        add("get_admin_routes",
            "Discover the current administrator’s navigation and CMS route templates.", [], true,
            _ -> {
                var reply:AdminReply = bridge.request("/admin/ai/routes");
                var catalog:Dynamic = reply.data;
                return McpServer.json({
                    data: {navigation: catalog.navigation, routes: catalog.routes}
                });
            });
        add("read_admin", "Read a native admin route when a specific tool is unavailable.",
            [field("path", path)], true, arguments -> call(arguments.path));
        add("write_admin",
            "Run a native form action when a specific tool is unavailable. Use its declared input fields.",
            [
                field("path", path),
                field("method", McpSchema.choice(["POST", "DELETE"])),
                optional("data", McpSchema.record())
            ], false,
            arguments -> call(arguments.path, arguments.method, arguments.data));
    }

    function registerLists():Void {
        var lists = [
            ["get_dashboard", "", "/admin", "Read CMS counts, recent content and activity."],
            [
                "list_collections",
                "",
                "/admin/collections",
                "List collections and their editor capabilities."
            ],
            ["list_categories", "taxonomy", "/admin/categories", "Search content categories."],
            ["list_tags", "taxonomy", "/admin/tags", "Search content tags."],
            [
                "list_media",
                "media",
                "/admin/media",
                "Search uploaded media and obtain managed image IDs and URLs."
            ],
            [
                "list_themes",
                "extensions",
                "/admin/themes",
                "Find installed themes and editable theme IDs."
            ],
            [
                "list_plugins",
                "extensions",
                "/admin/plugins",
                "Find installed plugins and their activation state."
            ],
            [
                "list_navigation",
                "navigation",
                "/admin/navigation",
                "Read navigation regions and links."
            ],
            [
                "get_site_settings",
                "settings",
                "/admin/settings",
                "Read site branding, language and homepage configuration."
            ],
            ["list_team", "team", "/admin/team", "Read the current team and assigned roles."],
            ["list_roles", "roles", "/admin/roles", "Read roles and their capability grants."],
            [
                "list_activity",
                "activity",
                "/admin/activity",
                "Read the admin activity history."
            ],
            ["get_account", "", "/admin/account", "Read your account profile."],
            [
                "list_backup_schedules",
                "backups",
                "/admin/backups",
                "Read backup schedule settings and recent run status."
            ]
        ];
        var page = [optional("q",
            McpSchema.string(80)), optional("cursor", McpSchema.string(1000))];
        for (entry in lists) {
            var capability = entry[1];
            var path = entry[2];
            if (capability == "" || can(capability)) {
                add(entry[0], entry[3], page, true, arguments -> call(browsePath(path, arguments)));
            }
        }
    }

    function registerTaxonomy():Void {
        add("save_category", "Create or rename a category.",
            [optional("id", id()), field("name", name())], false, arguments -> {
                var data = {
                    id: optionalId(arguments.id),
                    name: trimmed(arguments.name)
                };
                return call("/admin/categories/save", "POST", data);
            });
        add("save_tag", "Create or edit a tag.", [
            optional("id", id()),
            field("name", name()),
            field("slug", key()),
            optional("description", McpSchema.string(500))
        ], false, arguments -> {
            var data:Dynamic = {
                name: trimmed(arguments.name),
                slug: arguments.slug,
                id: optionalId(arguments.id)
            };
            if (arguments.description != null) {
                data.description = arguments.description;
            }
            return call("/admin/tags/save", "POST", data);
        });
        for (resource in ["categories", "tags"]) {
            var item = resource == "categories" ? "category" : "tag";
            var collection = resource;
            add('delete_${item}', 'Delete a ${item} through its native CMS checks.',
                [field("id", id())], false,
                arguments -> call('/admin/${collection}/${identifier(arguments)}/delete', "POST"));
        }
    }

    function registerMedia():Void {
        add("upload_media_image",
            "Stage a JPEG, PNG or GIF attachment or original Base64 image bytes. View the echoed image, verify its SHA-256 and measure its dimensions before calling verify_media_image.",
            [
                optional("base64", McpMediaInput.encoded()),
                optional("file", McpMediaInput.attachment()),
                optional("name", McpSchema.string(180))
            ], false, arguments -> {
                var upload = McpMediaInput.image(arguments.base64, arguments.file, arguments.name);
                var response = bridge.request("/admin/media/upload", "POST", null, upload);
                var checksum = Sha256.make(upload.bytes).toHex();
                if (response.status != 202 || response.image == null
                    || response.image.uploadId == null || response.image.sha256 != checksum) {
                    throw new Exception("The echoed upload does not match the original image.");
                }
                return AdminMcpBridge.result(response);
            }, McpMediaInput.fileParams);
        add("verify_media_image",
            "Save a staged media image after inspecting the echoed bytes. Supply the upload ID, SHA-256 and measured width and height. The result contains the managed image ID and URL.",
            [
                field("id", McpSchema.string(null, null, "^[A-Za-z0-9_-]{32}$")),
                field("sha256", McpSchema.string(null, null, "^[a-f0-9]{64}$")),
                field("width", McpSchema.integer(1, 10000)),
                field("height", McpSchema.integer(1, 10000))
            ], false,
            arguments -> call("/admin/media/upload/verify", "POST", arguments));
        add("read_media_image", "View a verified media library image by ID.", [field("id", id())],
            true, arguments -> call('/admin/ai/media/${identifier(arguments)}'));
        add("get_media_references",
            "Read the content, settings and plugin references to an image.", [field("id", id())],
            true, arguments -> call('/admin/media/${identifier(arguments)}/references'));
        add("update_media_details", "Save the title and alternative text of an uploaded image.", [
            field("id", id()),
            field("title", McpSchema.string(180)),
            field("alt", McpSchema.string(500))
        ], false,
            arguments -> call('/admin/media/${identifier(arguments)}/save', "POST", {
                title: arguments.title,
                alt: arguments.alt
            }));
        add("trash_media_image",
            "Move an uploaded image to the trash if the CMS finds no active references. Its public URL stops working; a person can restore it, and the trash deletes it after 30 days.",
            [field("id", id())], false,
            arguments -> call('/admin/media/${identifier(arguments)}/trash', "POST"));
        add("restore_media_image", "Restore an image from the trash.", [field("id", id())], false,
            arguments -> call('/admin/media/${identifier(arguments)}/restore', "POST"));
    }

    function registerNavigation():Void {
        add("list_navigation_regions", "Read the available navigation regions.", [], true,
            _ -> call("/admin/navigation/regions"));
        add("save_navigation_link",
            "Create or edit a navigation link to a path, published item or collection.", [
                optional("id", id()),
                field("label", McpSchema.string(80)),
                field("location", key()),
                field("position", McpSchema.integer(0, 9999)),
                optional("url", McpSchema.string(1000)),
                optional("contentId", id()),
                optional("collectionKey", key()),
                optional("language",
                    McpSchema.describe(languageCode(),
                        "Show the link only in this language; leave it out to show it in every language."))
            ], false, arguments -> {
                var position:Int = arguments.position;
                var data = {
                    id: optionalId(arguments.id),
                    label: arguments.label,
                    location: arguments.location,
                    position: '${position}',
                    url: arguments.url ?? "",
                    content_id: optionalId(arguments.contentId),
                    collection_key: arguments.collectionKey ?? "",
                    language: arguments.language ?? ""
                };
                return call("/admin/navigation/save", "POST", data);
            });
        add("delete_navigation_link", "Remove a navigation link by its ID.", [field("id", id())],
            false, arguments -> call('/admin/navigation/${identifier(arguments)}/delete', "POST"));
    }

    function registerExtensions():Void {
        var extensionId = McpSchema.string(100, null,
            "^(?:plugin|theme)-[a-z0-9]+(?:-[a-z0-9]+)*$");
        add("get_extension_settings", "Read editable settings for a theme or plugin.",
            [field("id", extensionId)], true, arguments -> {
                var extension:String = arguments.id;
                var area = StringTools.startsWith(extension, "theme-") ? "themes" : "plugins";
                return call('/admin/${area}/${extension}/settings');
            });
        for (action in ["enable", "disable"]) {
            var verb = action;
            var pluginId = McpSchema.string(100, null, "^plugin-[a-z0-9]+(?:-[a-z0-9]+)*$");
            add('${action == "enable" ? "activate" : "deactivate"}_plugin',
                '${action} an installed plugin through its native lifecycle.',
                [field("id", pluginId)], false, arguments -> {
                    var plugin:String = arguments.id;
                    return call('/admin/plugins/${plugin}/${verb}', "POST");
                });
        }
        add("create_theme_draft", "Create an editable theme draft from a built-in starter.", [
            field("name", name()),
            optional("starter", McpSchema.choice(["blank", "content"]))
        ], false,
            arguments -> call("/admin/themes/create", "POST", {
                name: trimmed(arguments.name),
                starter: arguments.starter ?? "blank"
            }));
        ThemeMcpTools.register(server, bridge.admin(),
            {read: true, edit: true, media: can("media")});
    }

    function registerSettings():Void {
        add("get_collection_definition",
            "Read the field schema and configuration for a content collection.",
            [field("key", key())], true, arguments -> {
                var collection:String = arguments.key;
                return call('/admin/content-types/${collection}/edit');
            });
        add("save_collection_definition",
            "Create or edit a collection using its native configuration fields.",
            [optional("key", key()), field("definition", McpSchema.record())], false,
            arguments -> {
                var collection:Null<String> = arguments.key;
                var path = collection != null ? '/admin/content-types/${collection}/save' : "/admin/content-types/create";
                return call(path, "POST", arguments.definition);
            });
        add("save_site_settings",
            "Save the complete site settings form after reading get_site_settings.",
            [field("settings", McpSchema.record())], false,
            arguments -> call("/admin/settings", "POST", arguments.settings));
        registerLanguages();
    }

    static function languageCode():Dynamic {
        return McpSchema.describe(McpSchema.string(35, 2,
            "^[a-z]{2,3}(?:-[A-Z][a-z]{3})?(?:-(?:[A-Z]{2}|[0-9]{3}))?$"),
            "A language code such as en, de, pt-BR or zh-Hant-TW. It is also the address prefix of the language.");
    }

    /**
        The site's languages. The default language has no address prefix and
        every other one is served under its code; a disabled language keeps its
        content but visitors cannot read it.
    **/
    function registerLanguages():Void {
        add("list_languages",
            "List the site's languages in order, with the default language, whether each is public, and its optional homepage.",
            [], true, _ -> call("/admin/languages"));
        add("save_language",
            "Add a language, or edit one: its name, writing direction, whether visitors can read it and its optional homepage. Pass originalCode to change the code of an existing language.",
            [
                field("code", languageCode()),
                field("name", McpSchema.string(60, 1)),
                optional("direction", McpSchema.choice(["ltr", "rtl"])),
                optional("enabled", McpSchema.boolean()),
                optional("homePageId",
                    McpSchema.describe(McpSchema.integer(0, MAX_ID),
                        "Published content shown as the language's homepage; 0 shows the translation of the site's homepage.")),
                optional("originalCode", languageCode())
            ], false, arguments -> {
                var enabled:Null<Bool> = arguments.enabled;
                var home:Null<Int> = arguments.homePageId;
                var data = {
                    code: arguments.code,
                    name: trimmed(arguments.name),
                    direction: arguments.direction ?? "ltr",
                    enabled: enabled == false ? "0" : "1",
                    home_page_id: home == null ? "0" : '${home}',
                    original_code: arguments.originalCode ?? ""
                };
                return call("/admin/languages/save", "POST", data);
            });
        add("reorder_languages", "Save the display order of every site language.",
            [field("order", McpSchema.array(languageCode(), 1, 32))], false, arguments -> {
                var order:Array<String> = arguments.order;
                return call("/admin/languages/order", "POST", {order: order.join(",")});
            });
        add("set_default_language",
            "Make a language the default. Its addresses lose their prefix and it becomes public.",
            [field("code", languageCode())], false,
            arguments -> call("/admin/languages/default", "POST", {
                code: arguments.code
            }));
        add("delete_language",
            "Delete a language that no content, navigation link or homepage uses. The default language cannot be deleted.",
            [field("code", languageCode())], false, arguments -> {
                var code:String = arguments.code;
                return call('/admin/languages/${StringTools.urlEncode(code)}/delete', "POST");
            });
    }

    /** Tools that plugins declare on their admin routes with `cms.mcp`. **/
    function registerPluginTools():Void {
        for (tool in AdminMcpPolicy.pluginTools(grants)) {
            var schema:Dynamic = tool.inputSchema;
            if (!McpSchema.isObject(schema) || schema.type != "object" || server.hasTool(tool.name)) {
                continue;
            }
            var path:String = tool.path;
            var method:String = tool.method;
            McpTools.addSchema(server, tool.name, tool.description, schema, method == "GET",
                arguments -> {
                    if (method != "GET") {
                        return call(path, method, arguments);
                    }
                    var parameters:Array<String> = [];
                    for (name in Reflect.fields(arguments)) {
                        var value:Dynamic = Reflect.field(arguments, name);
                        if (value == null) {
                            continue;
                        }
                        var text = Std.isOfType(value, String) ? value : Json.stringify(value);
                        parameters.push('${StringTools.urlEncode(name)}=${StringTools.urlEncode(text)}');
                    }
                    return call(parameters.length == 0 ? path : '${path}?${parameters.join("&")}');
                });
        }
    }
}
