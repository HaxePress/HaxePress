package hx.press.themes;

import haxe.Exception;
import haxe.Json;
import haxe.crypto.Base64;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import hx.press.ai.AdminMcpAccess;
import hx.press.ai.AdminMcpAccess.AdminMcpGrant;
import hx.press.mcp.InternalRequest;
import hx.press.mcp.InternalRequest.InternalReply;
import hx.press.mcp.McpMediaInput;
import hx.press.mcp.McpSchema;
import hx.press.mcp.McpSchema.McpField;
import hx.press.mcp.McpSchema.field;
import hx.press.mcp.McpSchema.optional;
import hx.press.mcp.McpServer;
import hx.press.mcp.McpSkills;
import hx.press.mcp.McpTools;
import hx.press.themes.ThemeAiPermissions.AiPermissions;
import hx.press.validation.Slug;
#if jvm
import hx.press.ServerSettings;
import hx.press.themes.ThemePreviewBrowser;
import hx.well.internal.SecureToken;
#end

/**
    The theme design tools: read the draft, apply visual-editor operations,
    replace the document, find and stage images and preview the design.
    A theme's own connection (the editor's browser) names them plainly and
    needs no theme ID; the admin connection names them for themes and takes
    the theme ID as an argument. Every call goes through the native theme
    designer API, which checks the per-theme AI permissions.
**/
class ThemeMcpTools {
    static final adminNames:Map<String, String> = [
        "get_design_guide" => "get_theme_design_guide",
        "get_design" => "get_theme_design",
        "edit_design" => "edit_theme_design",
        "replace_design" => "replace_theme_design",
        "search_media" => "search_media_for_theme",
        "get_collection_schema" => "get_theme_collection_schema",
        "read_media_image" => "read_media_for_theme",
        "search_theme_assets" => "search_theme_assets",
        "read_theme_asset_image" => "read_theme_asset_image",
        "upload_theme_image" => "upload_theme_image",
        "verify_theme_image" => "verify_theme_image",
        "preview_theme" => "preview_theme_design"
    ];

    /** Viewports of the preview tool, as the theme preview's device buttons show them. **/
    static final devices:Map<String, {width:Int, height:Int, mobile:Bool}> = [
        "desktop" => {width: 1280, height: 800, mobile: false},
        "tablet" => {width: 834, height: 1112, mobile: true},
        "mobile" => {width: 390, height: 844, mobile: true}
    ];

    static inline var THEME_ID_PATTERN = "^theme-[a-z0-9]+(?:-[a-z0-9]+)*$";
    static final imageTypes = ["image/jpeg", "image/png", "image/webp", "image/gif"];

    final server:McpServer;
    final grant:AdminMcpGrant;
    final themeId:Null<String>;
    final permissions:AiPermissions;

    function new(server:McpServer, grant:AdminMcpGrant, themeId:Null<String>,
            permissions:AiPermissions) {
        this.server = server;
        this.grant = grant;
        this.themeId = themeId;
        this.permissions = permissions;
    }

    /** The server of a theme's own connection, as the theme editor's browser uses it. **/
    public static function themeServer(grant:AdminMcpGrant, themeId:String,
            permissions:AiPermissions):McpServer {
        var server = new McpServer("haxepress-theme-editor", CmsVersion.version,
            permissions.read ? McpSkills.pointer : null);
        new ThemeMcpTools(server, grant, themeId, permissions).registerAll();
        return server;
    }

    /** Adds the theme tools to the admin connection, which names a theme in each call. **/
    public static function register(server:McpServer, grant:AdminMcpGrant,
            permissions:AiPermissions):Void {
        new ThemeMcpTools(server, grant, null, permissions).registerAll();
    }

    static function themeIdentifier():Dynamic {
        return McpSchema.string(80, null, THEME_ID_PATTERN);
    }

    function add(name:String, description:String, fields:Array<McpField>, isReadOnly:Bool,
            execute:(Dynamic, String) -> Dynamic, ?meta:Dynamic):Void {
        if (themeId != null || name == "get_design_guide") {
            var scoped = themeId;
            McpTools.add(server, scoped != null ? name : adminNames.get(name), description,
                fields, isReadOnly, arguments -> execute(arguments, scoped ?? ""), meta);
            return;
        }
        var extended = fields.concat([field("themeId", themeIdentifier())]);
        McpTools.add(server, adminNames.get(name) ?? name, description, extended, isReadOnly,
            arguments -> {
                var selected:String = arguments.themeId;
                Reflect.deleteField(arguments, "themeId");
                return execute(arguments, selected);
            }, meta);
    }

    function endpoint(theme:String):String {
        return '/api/theme-designer/${StringTools.urlEncode(theme)}';
    }

    function send(theme:String, path:String, method:String, headers:Map<String, String>,
            body:Null<Bytes>, limit:Int):InternalReply {
        if (!Slug.prefixed(theme, "theme-") || theme.length > 80) {
            throw new Exception("Choose a valid theme ID.");
        }
        return InternalRequest.send(method, '${endpoint(theme)}${path}', headers, body,
            [AdminMcpAccess.ACTOR => grant], limit);
    }

    static function contentType(reply:InternalReply):String {
        for (name => value in reply.headers) {
            if (name.toLowerCase() == "content-type") {
                return value.split(";")[0];
            }
        }
        return "";
    }

    static function headerValue(reply:InternalReply, header:String):Null<String> {
        for (name => value in reply.headers) {
            if (name.toLowerCase() == header.toLowerCase()) {
                return value;
            }
        }
        return null;
    }

    /** Calls the design API and returns its JSON; a refused request throws its error. **/
    function api(theme:String, path:String, ?data:Dynamic):Dynamic {
        var headers:Map<String, String> = ["Accept" => "application/json"];
        var body:Null<Bytes> = null;
        if (data != null) {
            headers.set("Content-Type", "application/json");
            body = Bytes.ofString(Json.stringify(data));
        }
        var reply = send(theme, path, data == null ? "GET" : "POST", headers, body,
            2 * ThemeDesignSchema.MAX_BYTES);
        if (contentType(reply) != "application/json") {
            throw new Exception("The CMS did not return a design API response.");
        }
        var result:Dynamic = Json.parse(reply.body.toString());
        if (reply.status < 200 || reply.status >= 300) {
            throw new Exception(Std.isOfType(result.error,
                String) ? result.error : "The CMS rejected this design request.");
        }
        return result;
    }

    static function identifier(arguments:Dynamic):Int {
        var id:Int = arguments.id;
        return id;
    }

    static function result(value:Dynamic):Dynamic {
        return McpServer.json(value);
    }

    static function safely(action:Void->Dynamic):Dynamic {
        try {
            return result(action());
        } catch (error:Exception) {
            return McpServer.failedTool(error.message);
        }
    }

    static function validateSize(document:Dynamic):String {
        var source = Json.stringify(document);
        if (Bytes.ofString(source).length > ThemeDesignSchema.MAX_BYTES) {
            throw new Exception("The theme design exceeds 1 MB.");
        }
        return source;
    }

    function current(theme:String, ?expectedVersion:Int):Dynamic {
        var data = api(theme, "/design");
        var saved:Int = data.theme.version;
        if (expectedVersion != null && saved != expectedVersion) {
            throw new Exception('The saved design changed. Read it again before editing. Current version: ${saved}');
        }
        return data;
    }

    static function query(values:Array<{name:String, value:Null<String>}>):String {
        var parts = [
            for (entry in values)
                if (entry.value != null && entry.value != "")
                    '${entry.name}=${StringTools.urlEncode(entry.value)}'
        ];
        return parts.length == 0 ? "" : '?${parts.join("&")}';
    }

    /** The `cursor` parameter of a pagination link, or `null`. **/
    static function cursorOf(link:Null<String>):Null<String> {
        if (link == null) {
            return null;
        }
        var start = link.indexOf("?");
        if (start < 0) {
            return null;
        }
        for (pair in link.substr(start + 1).split("&")) {
            var parts = pair.split("=");
            if (StringTools.urlDecode(parts[0]) == "cursor") {
                return StringTools.urlDecode(parts.slice(1).join("="));
            }
        }
        return null;
    }

    public static function guide():Dynamic {
        return {
            schema: 2,
            coreTemplates: ThemeDesignSchema.templates,
            blockTypes: ThemeDesignModel.blockTypes,
            htmlTags: ThemeDesignModel.htmlTags,
            layouts: ThemeDesignModel.layouts(),
            sections: [
                for (choice in ThemeDesignModel.sectionChoices)
                    {
                        id: choice.id,
                        name: choice.name
                    }
            ],
            limits: {
                bytes: ThemeDesignSchema.MAX_BYTES,
                nodes: ThemeDesignSchema.MAX_NODES,
                depth: ThemeDesignSchema.MAX_DEPTH,
                operations: 100,
                mediaPerDesign: 128,
                feedLimit: 24
            },
            workflow: "Read get_design and its version first. Use edit_design for small atomic changes, or replace_design for an entirely new theme. Design edits need expectedVersion and save a draft. The user reviews and publishes in the editor.",
            layout: "Sections own blocks. Containers, semantic elements and repeaters may own children. Core templates must remain present. Reusable components live in document.components and render with a component block. Add custom layouts in document.templates plus templateMeta with a label and core-template fallback.",
            content: "Use text, image and href for authored content. Use bindings.text=item.title, bindings.image=item.image, bindings.href=item.url for dynamic content. Set newTab true on a button, linked heading or image, or an a element to open a link that leaves the site in a new tab. A repeat block uses page.items, page.related or feed:<id>. Feeds are bounded collection queries with collection, limit, category, tag, query, order and direction. Plugin areas use extension blocks with slot names.",
            styles: "styles.desktop.normal is the base CSS map. styles.tablet and styles.mobile override it; hover and focus are independent states. CSS values are strings. Global tokens hold background, text, accent, font, width and radius. Shared appearances live in classes; css holds scoped theme CSS. Set an empty style value to inherit.",
            images: "Stage theme images with upload_theme_image, check the returned image, then call verify_theme_image with its ID, hash and dimensions. Use search_theme_assets or search_media to find existing images. Images and CSS backgrounds use the managed media library. Do not insert remote image URLs or executable HTML. Site branding and menu blocks use the CMS site settings and navigation.",
            identifiers: "Existing node IDs are stable. Insert and duplicate operations return fresh IDs. When replacing a document, use unique ASCII IDs up to 40 characters. Operations on nonexistent nodes or invalid nested moves fail without saving."
        };
    }

    static function selection():Dynamic {
        return McpSchema.object([
            field("scope", McpSchema.string(81, 1)),
            field("section", McpSchema.string(40)),
            optional("block", McpSchema.string(40))
        ]);
    }

    static function version():Dynamic {
        return McpSchema.integer(1, 999999999);
    }

    static function operations():Dynamic {
        var actions = [
            "insert",
            "section",
            "update",
            "style",
            "move",
            "remove",
            "duplicate",
            "tokens",
            "css"
        ];
        var destination = McpSchema.extend(selection(),
            [optional("position", McpSchema.choice(["before", "after", "inside"]))]);
        var operation = McpSchema.object([
            field("action", McpSchema.choice(actions)),
            optional("target", selection()),
            optional("destination", destination),
            optional("preset", McpSchema.string(80)),
            optional("name", McpSchema.string(80)),
            optional("values", McpSchema.record()),
            optional("breakpoint", McpSchema.choice(["desktop", "tablet", "mobile"])),
            optional("state", McpSchema.choice(["normal", "hover", "focus"])),
            optional("text", McpSchema.string(64000))
        ]);
        return McpSchema.array(operation, 1, 100);
    }

    function registerAll():Void {
        if (permissions.read) {
            registerReading();
        }
        if (permissions.edit) {
            registerEditing();
        }
        if (permissions.media) {
            registerMediaSearch();
        }
        if (permissions.read) {
            add("get_collection_schema",
                "Read the public custom fields and display features of a specific content collection before binding them into a theme. It returns schema metadata, not content records.",
                [field("key", McpSchema.string(null, null, "^[a-z][a-z0-9_]{0,31}$"))], true,
                (arguments,
                        theme) -> safely(() -> api(theme,
                        '/collections/${StringTools.urlEncode(arguments.key)}')));
        }
        if (permissions.media) {
            add("read_media_image",
                "View one permitted library image before choosing it for a design. Accepts a media ID from search_media and returns image content, up to the native 5 MB limit.",
                [field("id", McpSchema.positive())], true,
                (arguments,
                        theme) -> readImage(theme, '/media/${identifier(arguments)}',
                        "The image is unavailable or this account cannot access the media library.",
                        "Choose a supported image under 5 MB.", "The image could not be read."));
        }
        if (permissions.read) {
            registerAssets();
        }
        if (permissions.edit) {
            registerUploads();
        }
        if (themeId == null && permissions.read) {
            registerInspection();
        }
        if (themeId == null && permissions.edit) {
            registerBlockImage();
        }
    }

    function registerReading():Void {
        var designGuide = guide();
        add("get_design_guide",
            "Read the HaxePress theme schema, layout primitives, bindings, native constraints and safe editing workflow.",
            [], true, (_, _) -> result(designGuide));
        var guideText = Json.stringify(designGuide);
        server.resource({
            uri: "haxepress://theme/design-guide",
            name: "design-guide",
            mimeType: "application/json",
            description: "The editable theme design contract.",
            read: () -> guideText
        });
        McpSkills.register(server);
        add("get_design",
            "Read the current saved draft, version and available content collections. Optionally return only the sections in a named scope.",
            [optional("scope", McpSchema.string(81))], true, (arguments, theme) -> safely(() -> {
                var data = current(theme);
                var scope:Null<String> = arguments.scope;
                if (scope == null || scope == "") {
                    return data;
                }
                var document:Dynamic = data.theme.document;
                if (!ThemeDesignModel.scopesFor(document).contains(scope)) {
                    throw new Exception("Choose an existing template, header, footer or @component scope.");
                }
                return {
                    name: data.theme.name,
                    version: data.theme.version,
                    publishedVersion: data.theme.publishedVersion,
                    scope: scope,
                    sections: ThemeDesignModel.sectionsFor(document, scope),
                    tokens: document.tokens,
                    collections: data.collections
                };
            }));
        #if jvm
        if (ThemePreviewBrowser.available()) {
            registerPreview();
        }
        #end
    }

    #if jvm
    function registerPreview():Void {
        var path = McpSchema.describe(McpSchema.withDefault(McpSchema.string(300, null,
            "^\\/(?!\\/)\\S*$"), "/"),
            "A site path, such as /, /about, /content/a-post or /content?category=News.");
        var device = McpSchema.withDefault(McpSchema.choice(["desktop", "tablet", "mobile"]),
            "desktop");
        var fullPage = McpSchema.describe(McpSchema.withDefault(McpSchema.boolean(), false),
            "Capture the whole page, up to 8,000 pixels tall, instead of the first screen.");
        var design = McpSchema.describe(McpSchema.withDefault(McpSchema.choice(["draft", "published"]),
            "draft"),
            "Show the saved draft or the published design.");
        add("preview_theme",
            "Look at the theme as visitors see it. Renders a page of the site with this theme in a browser and returns a screenshot, its title and the internal links to open next. Check the saved draft after editing, on desktop, tablet and mobile, and full pages for spacing further down.",
            [
                optional("path", path),
                optional("device", device),
                optional("fullPage", fullPage),
                optional("design", design)
            ], true, (arguments, theme) -> {
                try {
                    return preview(theme, arguments.path, arguments.device, arguments.fullPage,
                        arguments.design);
                } catch (error:Exception) {
                    return McpServer.failedTool(error.message);
                }
            });
    }

    function preview(theme:String, path:String, device:String, fullPage:Bool,
            design:String):Dynamic {
        var pass = api(theme, "/preview");
        var frame:String = pass.frame;
        var queryStart = path.indexOf("?");
        var pathname = queryStart < 0 ? path : path.substr(0, queryStart);
        var search = queryStart < 0 ? "" : path.substr(queryStart + 1);
        var parameters = [for (pair in search.split("&")) if (pair != "") pair];
        if (design == "draft") {
            parameters = parameters.filter(pair -> pair.split("=")[0] != "design");
            parameters.push("design=draft");
        }
        var suffix = pathname == "/" ? "" : pathname;
        var origin = 'http://127.0.0.1:${ServerSettings.port}';
        var queryText = parameters.length == 0 ? "" : '?${parameters.join("&")}';
        var url = '${origin}${frame}${suffix}${queryText}';
        var headers:Map<String, String> = [
            AdminMcpAccess.TICKET_HEADER => pass.ticket,
            "X-CSRF-TOKEN" => SecureToken.generate(32)
        ];
        var shot = ThemePreviewBrowser.capture(url, headers, devices.get(device), fullPage);
        // Links inside the preview point at the preview frame; report them as site paths.
        var seen:Map<String, Bool> = [];
        var links:Array<Dynamic> = [];
        for (link in shot.links) {
            var target = link.href;
            var start = target.indexOf("?");
            var linkPath = start < 0 ? target : target.substr(0, start);
            if (linkPath != frame && !StringTools.startsWith(linkPath, '${frame}/')) {
                continue;
            }
            var linkQuery = start < 0 ? [] : target.substr(start + 1)
                .split("&")
                .filter(pair -> pair != "" && pair.split("=")[0] != "design");
            var sitePath = linkPath.substr(frame.length);
            var site = '${sitePath == "" ? "/" : sitePath}${linkQuery.length == 0 ? "" : '?${linkQuery.join("&")}'}';
            if (!seen.exists(site)) {
                seen.set(site, true);
                links.push({path: site, text: link.text});
            }
        }
        var summary = {
            path: path,
            device: device,
            design: design,
            status: shot.status,
            title: shot.title,
            pageHeight: shot.height,
            headings: shot.headings,
            links: links
        };
        var content:Array<Dynamic> = [
            {type: "image", data: shot.image, mimeType: "image/jpeg"},
            {type: "text", text: Json.stringify(summary)}
        ];
        return {
            content: content,
            structuredContent: summary
        };
    }
    #end

    function registerEditing():Void {
        add("edit_design",
            "Apply up to 100 atomic edits to this theme draft using the shared visual-editor operations. It never publishes or activates a theme.",
            [field("expectedVersion", version()), field("operations", operations())], false,
            (arguments, theme) -> safely(() -> {
                var expected:Int = arguments.expectedVersion;
                var data = current(theme, expected);
                var document = ThemeDesignModel.copy(data.theme.document);
                var created = ThemeDesignOperations.apply(document, arguments.operations);
                var saved:Dynamic = api(theme, "/design", {
                    name: data.theme.name,
                    version: '${expected}',
                    design: validateSize(document)
                });
                var reply:Dynamic = Reflect.copy(saved);
                reply.created = created;
                return reply;
            }));
        add("replace_design",
            "Replace the entire saved theme draft with a schema-2 document after native CMS validation. Keep all core templates. Use this for a complete new design or changes to reusable components, custom templates, classes or feeds.",
            [
                field("expectedVersion", version()),
                optional("name", McpSchema.string(100, 2)),
                field("document", McpSchema.record())
            ], false, (arguments, theme) -> safely(() -> {
                var expected:Int = arguments.expectedVersion;
                var data = current(theme, expected);
                var name:Null<String> = arguments.name;
                return api(theme, "/design", {
                    name: name != null && name != "" ? name : data.theme.name,
                    version: '${expected}',
                    design: validateSize(arguments.document)
                });
            }));
    }

    function registerMediaSearch():Void {
        add("search_media",
            "Find managed images in the permitted media library. Results use bounded cursor pagination and contain URLs, descriptions and dimensions.",
            [
                optional("query", McpSchema.string(80)),
                optional("cursor", McpSchema.string(1000))
            ], true, (arguments, theme) -> safely(() -> {
                var parameters = query([
                    {name: "q", value: arguments.query},
                    {
                        name: "cursor",
                        value: arguments.cursor
                    }
                ]);
                var response:Dynamic = Reflect.copy(api(theme, '/media${parameters}'));
                response.nextCursor = cursorOf(response.pagination.next);
                response.previousCursor = cursorOf(response.pagination.previous);
                return response;
            }));
    }

    function registerAssets():Void {
        add("search_theme_assets",
            "Find images owned by this theme. They live in theme storage, are included in theme exports, and do not require access to the site media library.",
            [
                optional("query", McpSchema.string(80)),
                optional("cursor", McpSchema.string(1000))
            ], true, (arguments, theme) -> safely(() -> {
                var parameters = query([
                    {name: "q", value: arguments.query},
                    {
                        name: "cursor",
                        value: arguments.cursor
                    }
                ]);
                var response:Dynamic = Reflect.copy(api(theme, '/assets${parameters}'));
                response.nextCursor = cursorOf(response.pagination.next);
                return response;
            }));
        add("read_theme_asset_image",
            "View an image owned by this theme, using an ID returned by search_theme_assets. It reads the theme image store, not the site media library.",
            [field("id", McpSchema.positive())], true,
            (arguments,
                    theme) -> readImage(theme, '/assets/${identifier(arguments)}',
                    "Choose an available image owned by this theme.",
                    "Choose a supported theme image.", "The theme image could not be read."));
    }

    function readImage(theme:String, path:String, unavailable:String, unsupported:String,
            fallback:String):Dynamic {
        try {
            var reply = send(theme, path, "GET", [], null, McpMediaInput.MAX_IMAGE_BYTES);
            if (reply.status < 200 || reply.status >= 300) {
                throw new Exception(unavailable);
            }
            var mimeType = contentType(reply);
            if (!imageTypes.contains(mimeType)) {
                throw new Exception(unsupported);
            }
            return {
                content: [
                    {
                        type: "image",
                        mimeType: mimeType,
                        data: Base64.encode(reply.body)
                    }
                ]
            };
        } catch (error:Exception) {
            var message = error.message == "The CMS response exceeds its size limit." ? "Choose an image under 5 MB." : error.message;
            return McpServer.failedTool(message == "" ? fallback : message);
        }
    }

    function registerUploads():Void {
        add("upload_theme_image",
            "Stage a JPEG, PNG or GIF attachment or canonical Base64 image, up to 5 MB. The response includes the uploaded image, its ID and SHA-256 hash. Check the image and call verify_theme_image to save it to this theme.",
            [
                optional("data", McpMediaInput.encoded()),
                optional("file", McpMediaInput.attachment()),
                optional("name", McpSchema.string(180))
            ], false, (arguments, theme) -> {
                try {
                    return upload(theme, arguments);
                } catch (error:Exception) {
                    return McpServer.failedTool(error.message);
                }
            }, McpMediaInput.fileParams);
        add("verify_theme_image",
            "Confirm a staged theme image after checking that it displays and matches the original file. Supply the upload ID, SHA-256 hash and measured pixel dimensions. The result includes its saved theme image URL.",
            [
                field("id", McpSchema.string(null, null, "^[A-Za-z0-9_-]{32}$")),
                field("sha256", McpSchema.string(null, null, "^[a-f0-9]{64}$")),
                field("width", McpSchema.integer(1, 10000)),
                field("height", McpSchema.integer(1, 10000))
            ], false,
            (arguments, theme) -> safely(() -> api(theme, "/assets/verify", arguments)));
    }

    function upload(theme:String, arguments:Dynamic):Dynamic {
        var image = McpMediaInput.image(arguments.data, arguments.file, arguments.name);
        var label = image.name ?? "Theme image";
        var headers:Map<String, String> = [
            "Accept" => "image/*, application/json",
            "Content-Type" => "application/octet-stream",
            "X-File-Name" => StringTools.urlEncode(label)
        ];
        var reply = send(theme, "/assets", "POST", headers, image.bytes,
            McpMediaInput.MAX_IMAGE_BYTES);
        if (reply.status != 202) {
            var reason:Null<String> = null;
            if (contentType(reply) == "application/json") {
                var parsed:Dynamic = Json.parse(reply.body.toString());
                reason = parsed.error;
            }
            throw new Exception(reason ?? "The theme image could not be uploaded.");
        }
        var id = headerValue(reply, "X-Upload-Id");
        var mimeType = contentType(reply);
        var sha256 = Sha256.make(reply.body).toHex();
        var original = Sha256.make(image.bytes).toHex();
        if (id == null || sha256 != original
            || !["image/jpeg", "image/png", "image/gif"].contains(mimeType)) {
            throw new Exception("The uploaded image does not match the selected file.");
        }
        var pending = result({id: id, sha256: sha256});
        var content:Array<Dynamic> = pending.content;
        content.push({type: "image", mimeType: mimeType, data: Base64.encode(reply.body)});
        return pending;
    }

    function registerInspection():Void {
        add("inspect_theme_tree",
            "List template, shared layout and component scopes with their section and block IDs. Use the IDs for targeted design changes.",
            [optional("scope", McpSchema.string(81))], true, (arguments, theme) -> safely(() -> {
                var data = current(theme);
                var document:Dynamic = data.theme.document;
                var available = ThemeDesignModel.scopesFor(document);
                var scope:Null<String> = arguments.scope;
                var selected = scope != null && scope != "";
                if (selected && !available.contains(scope)) {
                    throw new Exception("Choose an existing theme scope.");
                }
                var scopes = selected ? [scope] : available;
                return {
                    version: data.theme.version,
                    scopes: [
                        for (name in scopes)
                            {
                                name: name,
                                sections: [
                                    for (section in ThemeDesignModel.sectionsFor(document, name))
                                        {
                                            id: section.id,
                                            name: section.name,
                                            blocks: summarize(section.blocks)
                                        }
                                ]
                            }
                    ]
                };
            }));
        add("get_theme_section",
            "Read one theme section with its nested blocks, bindings, responsive styles and IDs.",
            [field("scope", McpSchema.string(81)), field("sectionId", McpSchema.string(40))],
            true, (arguments, theme) -> safely(() -> {
                var data = current(theme);
                var sections = ThemeDesignModel.sectionsFor(data.theme.document, arguments.scope);
                var section = ThemeDesignModel.findSection(sections, arguments.sectionId);
                if (section == null) {
                    throw new Exception("Choose an existing section from inspect_theme_tree.");
                }
                return {version: data.theme.version, scope: arguments.scope, section: section};
            }));
    }

    static function summarize(blocks:Null<Array<Dynamic>>):Array<Dynamic> {
        if (blocks == null) {
            return [];
        }
        return [
            for (block in blocks)
                {id: block.id, type: block.type, children: summarize(block.children)}
        ];
    }

    function registerBlockImage():Void {
        var target = McpSchema.extend(selection(), [field("block", McpSchema.string(40, 1))]);
        add("set_theme_block_image",
            "Set a block’s image using the managed URL returned by verify_theme_image or search_theme_assets. Saves the theme draft.",
            [
                field("expectedVersion", version()),
                field("target", target),
                field("imageUrl", McpSchema.string(500)),
                optional("alt", McpSchema.string(500))
            ], false, (arguments, theme) -> safely(() -> {
                var expected:Int = arguments.expectedVersion;
                var data = current(theme, expected);
                var document = ThemeDesignModel.copy(data.theme.document);
                var values:Dynamic = {image: arguments.imageUrl};
                if (arguments.alt != null) {
                    values.alt = arguments.alt;
                }
                ThemeDesignOperations.apply(document,
                    [{action: "update", target: arguments.target, values: values}]);
                return api(theme, "/design", {
                    name: data.theme.name,
                    version: '${expected}',
                    design: validateSize(document)
                });
            }));
    }
}
