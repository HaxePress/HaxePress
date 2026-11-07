package hx.press.ai;

import haxe.Exception;
import haxe.Json;
import hx.press.mcp.McpSchema;
import hx.press.mcp.McpSchema.McpField;
import hx.press.mcp.McpSchema.field;
import hx.press.mcp.McpSchema.optional;
import hx.press.mcp.McpServer;
import hx.press.mcp.McpTools;

/**
    Content tools of the admin MCP catalog: find, read, create and update
    items of any collection, publish them, move them to the trash and back,
    work with revisions and attach verified media images. Edits name the
    version they were read at and keep the fields they do not change.
**/
class AdminMcpContentTools {
    final server:McpServer;
    final bridge:AdminMcpBridge;
    final canMedia:Bool;
    final canPublish:Bool;

    public function new(server:McpServer, bridge:AdminMcpBridge, canMedia:Bool, canPublish:Bool) {
        this.server = server;
        this.bridge = bridge;
        this.canMedia = canMedia;
        this.canPublish = canPublish;
    }

    static function kind():Dynamic {
        return McpSchema.describe(McpSchema.string(null, null, "^[a-z][a-z0-9_]{0,31}$"),
            "Collection key, such as entry for articles, page for pages, or a custom collection key.");
    }

    static function id():Dynamic {
        return McpSchema.integer(1, McpSchema.MAX_INT);
    }

    static function documentKey():Array<McpField> {
        return [field("collection", kind()), field("id", id())];
    }

    static function currentDocument():Array<McpField> {
        return documentKey().concat([field("expectedVersion", id())]);
    }

    static function contentFields():Dynamic {
        return McpSchema.object([
            optional("title", McpSchema.string(180, 1)),
            optional("slug", McpSchema.string(180, null, "^[a-z0-9]+(?:-[a-z0-9]+)*$")),
            optional("excerpt", McpSchema.string(500)),
            optional("body", McpSchema.string(100000)),
            optional("category", McpSchema.string(80)),
            optional("tagIds", McpSchema.array(id(), null, 100)),
            optional("featured",
                McpSchema.describe(McpSchema.boolean(),
                    "Feature the item on the homepage. A collection has one featured item: featuring this one removes the mark from the previous one.")),
            optional("status", McpSchema.choice(["draft", "published", "scheduled"])),
            optional("publishDate", McpSchema.string(50)),
            optional("scheduledEpoch", McpSchema.number(0)),
            optional("seoTitle", McpSchema.string(180)),
            optional("seoDescription", McpSchema.string(500)),
            optional("customFields", McpSchema.record())
        ]);
    }

    static function collectionPath(collection:String):String {
        return '/admin/collections/${collection}';
    }

    /** The admin path of one item of the document named by `arguments`, plus `suffix`. **/
    static function itemPath(arguments:Dynamic, suffix:String):String {
        var collection:String = arguments.collection;
        var id:Int = arguments.id;
        return '${collectionPath(collection)}/${id}${suffix}';
    }

    function add(name:String, description:String, fields:Array<McpField>, isReadOnly:Bool,
            run:Dynamic->Dynamic):Void {
        McpTools.add(server, name, description, fields, isReadOnly, run);
    }

    function call(path:String, method:String = "GET", ?data:Dynamic):Dynamic {
        return AdminMcpBridge.result(bridge.request(path, method, data));
    }

    static function pick(changes:Dynamic, change:String, item:Null<Dynamic>, saved:String,
            fallback:Dynamic):Dynamic {
        var value:Dynamic = changes == null ? null : Reflect.field(changes, change);
        if (value != null) {
            return value;
        }
        var stored:Dynamic = item == null ? null : Reflect.field(item, saved);
        return stored ?? fallback;
    }

    static function truthy(value:Dynamic):Bool {
        return value == true || (value != null && value != false && value != 0 && value != "");
    }

    /** The editor form fields for `changes` applied to the saved `item`. **/
    static function saveFields(changes:Dynamic, ?item:Dynamic):Dynamic {
        var featured:Dynamic = changes.featured ?? truthy(item?.featured);
        var published:Null<String> = item?.published_at;
        var tagIds:Array<Dynamic> = changes.tagIds ?? [
            for (tag in ((item?.tags ?? []) : Array<Dynamic>))
                tag.id
        ];
        var customFields:Dynamic = changes.customFields ?? item?.fields ?? {};
        return {
            title: pick(changes, "title", item, "title", ""),
            slug: pick(changes, "slug", item, "slug", ""),
            excerpt: pick(changes, "excerpt", item, "excerpt", ""),
            content: pick(changes, "body", item, "content", ""),
            category: pick(changes, "category", item, "category", ""),
            image: item?.image ?? "",
            image_alt: item?.image_alt ?? "",
            status: pick(changes, "status", item, "status", "draft"),
            featured: featured == true ? "1" : "0",
            published_at: changes.publishDate ?? (published == null ? "" : published.substr(0, 10)),
            scheduled_epoch: AdminMcpServer.numberText(changes.scheduledEpoch ?? item?.scheduled_epoch ?? 0),
            tags: [for (tag in tagIds) AdminMcpServer.numberText(tag)].join(","),
            seo_title: pick(changes, "seoTitle", item, "seo_title", ""),
            seo_description: pick(changes, "seoDescription", item, "seo_description", ""),
            custom_fields: Json.stringify(customFields)
        };
    }

    /** The editor page of the saved item at the expected version. **/
    function editor(document:Dynamic):Dynamic {
        var reply = bridge.request(itemPath(document, "/edit"));
        var page:Dynamic = reply.data;
        if (page == null || page.component != "Admin/Editor" || page.props == null) {
            throw new Exception("The content editor is unavailable.");
        }
        var props:Dynamic = page.props;
        var saved:Int = props.item.version;
        var expected:Int = document.expectedVersion;
        if (saved != expected) {
            throw new Exception('The content changed. Read version ${saved} before editing.');
        }
        if (truthy(props.workingCopy)) {
            throw new Exception("Save or discard the open working copy in the editor before changing this item.");
        }
        return props;
    }

    function save(document:Dynamic, fields:Dynamic):Dynamic {
        var collection:String = document.collection;
        var id:Int = document.id;
        var expected:Int = document.expectedVersion;
        var data:Dynamic = Reflect.copy(fields);
        data.id = '${id}';
        data.version = '${expected}';
        data.stay = "1";
        return call('${collectionPath(collection)}/save', "POST", data);
    }

    public function register():Void {
        add("list_content",
            "Find content in a collection with bounded search, status and cursor filters.", [
                field("collection", kind()),
                optional("query", McpSchema.string(120)),
                optional("status", McpSchema.choice(["draft", "published", "scheduled", "trash"])),
                optional("cursor", McpSchema.string(1000))
            ], true, arguments -> {
                var parameters:Array<String> = [];
                for (entry in [
                    {name: "q", value: arguments.query},
                    {name: "status", value: arguments.status},
                    {name: "cursor", value: arguments.cursor}
                ]) {
                    var value:Null<String> = entry.value;
                    if (value != null && value != "") {
                        parameters.push('${entry.name}=${StringTools.urlEncode(value)}');
                    }
                }
                var collection:String = arguments.collection;
                var path = collectionPath(collection);
                return call(parameters.length == 0 ? path : '${path}?${parameters.join("&")}');
            });
        add("get_content",
            "Read one item, including its body, managed media and current version.",
            documentKey(), true, arguments -> call(itemPath(arguments, "/edit")));
        var required = McpSchema.requiring(contentFields(), ["title", "slug"]);
        add("create_content", "Create content in a collection. Draft is the default status.",
            [field("collection", kind()), field("fields", required)], false, arguments -> {
                var collection:String = arguments.collection;
                return call('${collectionPath(collection)}/save', "POST",
                    saveFields(arguments.fields));
            });
        add("update_content",
            "Update selected fields on the saved item using its current version.",
            currentDocument().concat([field("fields", contentFields())]), false, arguments -> {
                var props = editor(arguments);
                return save(arguments, saveFields(arguments.fields, props.item));
            });
        if (canPublish) {
            add("publish_content", "Publish the saved version of an item.", currentDocument(),
                false, arguments -> {
                    var props = editor(arguments);
                    return save(arguments, saveFields({status: "published"}, props.item));
                });
        }
        // Only people can delete content permanently; the CMS refuses it for MCP clients.
        for (entry in [
            {
                tool: "trash_content",
                operation: "trash",
                description: "Move a content item to the trash. A person can restore it or delete it permanently."
            },
            {
                tool: "restore_content",
                operation: "restore",
                description: "Restore a trashed content item."
            }
        ]) {
            var operation = entry.operation;
            add(entry.tool, entry.description, documentKey(), false,
                arguments -> call(itemPath(arguments, '/${operation}'), "POST"));
        }
        add("list_content_revisions", "Read the revision history for one content item.",
            documentKey(), true, arguments -> call(itemPath(arguments, "/history")));
        var revision = documentKey().concat([field("revision", id())]);
        add("get_content_revision", "Read one historical version of a content item.", revision,
            true, arguments -> {
                var revision:Int = arguments.revision;
                return call(itemPath(arguments, '/history/${revision}'));
            });
        add("restore_content_revision",
            "Restore a historical version through the CMS history workflow.", revision, false,
            arguments -> {
                var revision:Int = arguments.revision;
                return call(itemPath(arguments, '/history/${revision}/restore'), "POST");
            });
        if (canMedia) {
            registerMedia();
        }
    }

    function media(mediaId:Int):Dynamic {
        var reply = bridge.request('/admin/ai/media/${mediaId}/info');
        var image:Dynamic = reply.data;
        if (image == null || image.url == null || image.url == "") {
            throw new Exception("Choose a verified media library image.");
        }
        return image;
    }

    function registerMedia():Void {
        var attachment = currentDocument().concat([field("mediaId",
            id()), optional("alt", McpSchema.string(500))]);
        add("set_content_cover",
            "Set the cover from a verified media ID. Use upload_media_image and verify_media_image before attaching a new upload.",
            attachment, false, arguments -> {
                var props = editor(arguments);
                var features:Array<String> = props.contentType.features;
                if (!features.contains("image")) {
                    throw new Exception("This collection does not have a cover image field.");
                }
                var image = media(arguments.mediaId);
                var fields:Dynamic = saveFields({}, props.item);
                fields.image = image.url;
                fields.image_alt = arguments.alt ?? image.alt;
                return save(arguments, fields);
            });
        add("insert_content_image",
            "Insert a verified media image at the start or end of an article’s Markdown body.",
            attachment.concat([optional("position", McpSchema.choice(["start", "end"]))]), false,
            arguments -> {
                var props = editor(arguments);
                var features:Array<String> = props.contentType.features;
                if (!features.contains("body")) {
                    throw new Exception("This collection does not have a Markdown body.");
                }
                var image = media(arguments.mediaId);
                var alt:String = arguments.alt ?? image.alt ?? "";
                var text = ~/[\\\[\]]/g.map(~/[\r\n]/g.replace(alt, " "),
                    match -> '\\${match.matched(0)}');
                var url:String = image.url;
                var markdown = '![${text}](${url})';
                var content:String = props.item.content ?? "";
                var body = arguments.position == "start" ? '${markdown}\n\n${content}' : '${content}\n\n${markdown}';
                return save(arguments, saveFields({body: body}, props.item));
            });
    }
}
