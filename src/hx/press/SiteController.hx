package hx.press;

import hx.press.i18n.PageSeo;
import hx.press.i18n.LanguageChoices;
import hx.press.i18n.Languages;
import hx.press.content.ContentAlternates;
import hx.press.view.View;
import hx.press.view.ViewRoots;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.TagData.TagRecord;
import hx.press.content.ContentTypes;
import hx.press.content.ContentFields;
import hx.press.content.ContentViews;
import hx.press.content.ContentFields.ContentFieldFilter;
import hx.press.content.ContentTypeDefinition;
import hx.press.data.ContentItemRecord;
import hx.press.plugins.PluginRuntime;
import hx.press.ContentItemData.DraftContentDetails;

using StringTools;

class SiteController {
    /**
        The public values of a preview rendered inside the administration:
        theme templates there see the site as a visitor does, without the
        administrator's account or CSRF token.
    **/
    public static function appearance(theme:Dynamic, path:String):Map<String, Dynamic> {
        return [
            "auth" => null,
            "csrfToken" => null,
            "theme" => theme,
            "navigation" => theme == null ? null : NavigationData.forRegions(theme.navigation),
            "pluginNavigation" => {
                header: theme == null ? [] : PluginRuntime.navigation("header", []),
                footer: theme == null ? [] : PluginRuntime.navigation("footer", []),
                admin: []
            },
            "extensions" => ViewRoots.extensionValues(theme == null ? [] : PluginRuntime.assets(),
                theme == null ? [] : PluginRuntime.blocks("site.shared", {
                    path: path
                }))
        ];
    }

    public static function home(request:Request):AbstractResponse {
        var settings = SiteSettingsStore.settings();
        var homeType = settings.get("home_type") ?? "entry";
        if (settings.get("home_mode") == "page") {
            var id = Std.parseInt(settings.get("home_page") ?? "0") ?? 0;
            var page = ContentQueries.homePage(id);
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
        return View.render(template, props);
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
        return View.render(type.archiveTemplate, props);
    }

    public static function content(request:Request, kind:String,
            slug:String = ""):AbstractResponse {
        var type = ContentTypes.find(kind);
        if (type == null || !type.publicVisible) {
            return notFound(request);
        }
        var requested = slug == "" ? request.route("slug") : slug;
        var item = ContentQueries.publishedItem(requested, kind);
        if (item == null) {
            // Another language's address of content that is translated into this one.
            var translated = ContentQueries.translatedSlug(requested, kind);
            if (translated != null) {
                var target = '${type.publicBase}/${StringTools.urlEncode(translated)}';
                return ResponseBuilder.asRedirect(Languages.path(Languages.current(), target), 301);
            }
            return notFound(request);
        }
        var settings = SiteSettingsStore.settings();
        var homeId = Std.parseInt(settings.get("home_page") ?? "0") ?? 0;
        var home = settings.get("home_mode") == "page" ? ContentQueries.homePage(homeId) : null;
        if (home != null && home.id == item.id) {
            var previewBase:String = request.getAttribute("hx.press.preview.base", "");
            return
                ResponseBuilder.asRedirect(previewBase == "" ? Languages.path(Languages.current(),
                    "/") : previewBase, 301);
        }
        return renderDocument(request, item, type);
    }

    public static function renderDocument(request:Request, item:ContentItemRecord,
            type:ContentTypeDefinition, home:Bool = false,
            ?draft:DraftContentDetails):AbstractResponse {
        if (draft == null) {
            ContentViews.shown(request, item.id, type.key);
            request.setAttribute(LanguageChoices.ALTERNATES,
                ContentAlternates.of(item, type, home));
            if (!home) {
                var own = item.language == "" ? Languages.defaultCode() : item.language;
                request.setAttribute(PageSeo.CONTENT, {
                    canonical: Languages.path(own,
                        '${type.publicBase}/${StringTools.urlEncode(item.slug)}'),
                    group: item.translation_group,
                    kind: type.key,
                    publicBase: type.publicBase
                });
            }
        }
        var relatedRecords = type.hasArchive ? ContentQueries.related(item.id, type.key) : [];
        var content = ContentItemData.detail(item, true, type, draft);
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
        return View.render(type.template, props);
    }

    public static function about(request:Request):AbstractResponse {
        request.setAttribute("hx.press.theme.template", "About");
        request.setAttribute("hx.press.theme.fallback", "About");
        return View.render("About");
    }

    public static function notFound(request:Request):AbstractResponse {
        request.setAttribute("hx.press.theme.template", "NotFound");
        request.setAttribute("hx.press.theme.fallback", "NotFound");
        return View.render("NotFound").status(404);
    }
}
