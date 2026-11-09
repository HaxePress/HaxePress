package extensions.rss;

import hx.press.content.ContentTranslations;
import hx.press.i18n.SiteTexts;
import hx.press.i18n.Languages;
import hx.press.ContentCache;
import hx.press.SiteSettingsStore;
import hx.press.content.ContentTypes;
import hx.well.facades.Environment;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.ContentItem;

typedef FeedItem = {var title:String; var slug:String; var excerpt:String;}

class RssHandler extends AbstractHandler {
    public function execute(request:Request):AbstractResponse {
        var settings = SiteSettingsStore.settings();
        var kind = settings.get("home_type") ?? "entry";
        var type = ContentTypes.find(kind);
        if (type == null || !type.publicVisible) {
            return ResponseBuilder.asString("Feed collection not found.", 404);
        }
        // Each site language has its own feed under its prefix, such as /de/rss.xml.
        var language = Languages.current();
        var items:Array<FeedItem> = ContentCache.remember("items", "rss",
            [kind, 50, ContentTypes.revision(), language], () -> {
                var query = ContentItem.query.select(["title", "slug", "excerpt"])
                    .where("content_type", kind)
                    .where("status", "published");
                ContentTranslations.visibleIn(query, kind, language);
                return query.orderBy("published_at", "DESC")
                    .orderBy("id", "DESC")
                    .limit(50)
                    .get()
                    .map(model -> cast model.toObject());
            });
        var baseUrl = Environment.env("APP_URL", "http://127.0.0.1:3000");
        var document = Xml.createDocument();
        document.addChild(Xml.createProcessingInstruction('xml version="1.0" encoding="UTF-8"'));
        var rss = Xml.createElement("rss");
        rss.set("version", "2.0");
        document.addChild(rss);
        var channel = Xml.createElement("channel");
        rss.addChild(channel);
        var site = SiteTexts.settings(settings);
        add(channel, "title", site.get("site_name"));
        add(channel, "link", '${baseUrl}${Languages.path(language, "/")}');
        add(channel, "description", site.get("description"));
        add(channel, "language", language);
        for (item in items) {
            var feedItem = Xml.createElement("item");
            var path = '${type.publicBase}/${StringTools.urlEncode(item.slug)}';
            var url = '${baseUrl}${Languages.path(language, path)}';
            add(feedItem, "title", item.title);
            add(feedItem, "link", url);
            add(feedItem, "guid", url);
            add(feedItem, "description", item.excerpt);
            channel.addChild(feedItem);
        }
        return ResponseBuilder.asString(document.toString())
            .header("Content-Type", "application/rss+xml; charset=utf-8");
    }

    static function add(parent:Xml, name:String, value:String):Void {
        var element = Xml.createElement(name);
        element.addChild(Xml.createPCData(value));
        parent.addChild(element);
    }
}
