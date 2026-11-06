package hx.press;

import hx.well.facades.Inertia;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.TagData.TagRecord;
import hx.press.content.ContentTypes;
import hx.press.content.ContentFields;
import hx.press.content.ContentFields.ContentFieldFilter;
import hx.press.content.ContentTypeDefinition;
import hx.press.data.ContentItemRecord;
import hx.press.plugins.PluginRuntime;

using StringTools;

class SiteController {
    public static function home(request:Request):AbstractResponse {
        var settings = SiteSettingsStore.settings();
        var homeType = settings.get("home_type") ?? "entry";
        if (settings.get("home_mode") == "page") {
            var id = Std.parseInt(settings.get("home_page") ?? "0") ?? 0;
            var page = ContentQueries.publishedById(id);
            if (page == null) {
                return notFound(request);
            }
            var type = ContentTypes.find(page.content_type);
            return type == null
                || !type.publicVisible ? notFound(request) : renderDocument(request, page, type,
                    true);
        }
        var type = ContentTypes.find(homeType);
        if (type == null || !type.publicVisible) {
            return notFound(request);
        }
        var limit = Std.parseInt(settings.get("home_size") ?? "7") ?? 7;
        limit = Std.int(Math.max(1, Math.min(24, limit)));
        var featuredRecord = ContentTypes.supports(type,
            "featured") ? ContentQueries.featured(type.key) : null;
        var featuredId = featuredRecord == null ? 0 : featuredRecord.id;
        var remaining = limit - (featuredRecord == null ? 0 : 1);
        var latestRecords = ContentQueries.latest(featuredId, type.key, remaining);
        var featuredContent = featuredRecord == null ? null : ContentItemData.summary(featuredRecord,
            type);
        var latestItems = [for (item in latestRecords) ContentItemData.summary(item, type)];
        var publishedCount = ContentQueries.publishedCount(type.key);
        var categories = ContentTypes.supports(type, "categories") ? CategoryData.names() : [];
        var props = {
            featured: featuredContent,
            items: latestItems,
            count: publishedCount,
            collection: ContentTypes.publicInfo(type),
            categories: categories,
            templateFallback: "Home"
        };
        var template = settings.get("home_template") ?? "Home";
        request.setAttribute("hx.press.theme.template", template);
        request.setAttribute("hx.press.theme.fallback", "Home");
        return Inertia.render(template, props);
    }

    public static function index(request:Request, kind:String,
            archiveTag:Null<TagRecord> = null):AbstractResponse {
        var type = ContentTypes.find(kind);
        if (type == null || !type.publicVisible) {
            return notFound(request);
        }
        var query = request.query("q", "").trim().substr(0, 120);
        var category = ContentTypes.supports(type,
            "categories") ? request.query("category", "").trim().substr(0, 80) : "";
        var tag = archiveTag;
        var requestedTag = request.query("tag", "").substr(0, 120);
        if (tag == null && requestedTag != "") {
            tag = TagData.named(requestedTag);
            if (tag == null) {
                return notFound(request);
            }
        }
        if (tag != null && !ContentTypes.supports(type, "tags")) {
            return notFound(request);
        }
        var tagId = tag == null ? 0 : tag.id;
        var filters:Array<ContentFieldFilter>;
        try {
            filters = ContentFields.filters(type, request);
        } catch (invalid:Dynamic) {
            return ResponseBuilder.asJson({error: Std.string(invalid)}, 422);
        }
        var cursor = Pagination.cursor(request);
        var page = ContentQueries.index(kind, query, category, cursor, tagId, filters);
        var resultCount = ContentQueries.indexCount(kind, query, category, tagId, filters);
        var publishedCount = tag == null ? ContentQueries.publishedCount(kind) : ContentQueries.indexCount(kind,
            "", "", tagId);
        var items = [for (item in page.items) ContentItemData.summary(item, type)];
        var archiveUrl = archiveTag == null ? type.publicBase : '/tags/${archiveTag.slug}';
        var parameters = ["q" => query, "category" => category];
        if (tag != null) {
            parameters.set("tag", tag.slug);
            parameters.set("type", kind);
        }
        var fieldFilters:Dynamic = {};
        for (filter in filters) {
            var value = Std.string(filter.value);
            parameters.set('field_${filter.key}', value);
            Reflect.setField(fieldFilters, filter.key, value);
        }
        var links = Pagination.links(archiveUrl, parameters, page, cursor, resultCount,
            item -> item.id,
            item ->
                item.published_at == null ? null : ContentItemData.dateValue(item.published_at));
        var categories = ContentTypes.supports(type,
            "categories") ? CategoryData.names(category) : [];
        var props = {
            items: items,
            query: query,
            category: category,
            tag: tag,
            total: publishedCount,
            resultCount: resultCount,
            archiveUrl: archiveUrl,
            pagination: links,
            collection: ContentTypes.publicInfo(type),
            categories: categories,
            fieldFilters: fieldFilters,
            templateFallback: "ContentIndex"
        };
        request.setAttribute("hx.press.theme.template", type.archiveTemplate);
        request.setAttribute("hx.press.theme.fallback", "ContentIndex");
        return Inertia.render(type.archiveTemplate, props);
    }

    public static function content(request:Request, kind:String,
            slug:String = ""):AbstractResponse {
        var type = ContentTypes.find(kind);
        if (type == null || !type.publicVisible) {
            return notFound(request);
        }
        var item = ContentQueries.publishedItem(slug == "" ? request.route("slug") : slug, kind);
        if (item == null) {
            return notFound(request);
        }
        var settings = SiteSettingsStore.settings();
        if (settings.get("home_mode") == "page" && Std.string(item.id) == settings.get("home_page")) {
            var previewBase:String = request.getAttribute("hx.press.preview.base", "");
            return ResponseBuilder.asRedirect(previewBase == "" ? "/" : previewBase, 301);
        }
        return renderDocument(request, item, type);
    }

    public static function renderDocument(request:Request, item:ContentItemRecord,
            type:ContentTypeDefinition, home:Bool = false):AbstractResponse {
        var relatedRecords = type.hasArchive ? ContentQueries.related(item.id, type.key) : [];
        var content = ContentItemData.detail(item, true);
        content.content = PluginRuntime.render(content);
        if (home) {
            content.url = "/";
        }
        var relatedItems = [for (related in relatedRecords) ContentItemData.summary(related, type)];
        var props = {
            item: content,
            related: relatedItems,
            collection: ContentTypes.publicInfo(type),
            templateFallback: type.hasArchive ? "ContentDetail" : "Page"
        };
        request.setAttribute("hx.press.theme.template", type.template);
        request.setAttribute("hx.press.theme.fallback", type.hasArchive ? "ContentDetail" : "Page");
        return Inertia.render(type.template, props);
    }

    public static function about(request:Request):AbstractResponse {
        request.setAttribute("hx.press.theme.template", "About");
        request.setAttribute("hx.press.theme.fallback", "About");
        return Inertia.render("About");
    }

    public static function notFound(request:Request):AbstractResponse {
        request.setAttribute("hx.press.theme.template", "NotFound");
        request.setAttribute("hx.press.theme.fallback", "NotFound");
        return Inertia.render("NotFound").status(404);
    }
}
