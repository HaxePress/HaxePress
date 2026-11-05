package hx.press.themes;

import hx.press.ContentQueries;
import hx.press.ContentItemData;
import hx.press.TagData;
import hx.press.content.ContentTypes;

class ThemeFeedData {
    static function used(blocks:Array<Dynamic>, document:Dynamic, sources:Map<String, Bool>,
            components:Map<String, Bool>):Void {
        for (block in blocks) {
            var source:String = block.source;
            if (block.type == "repeat" && source != null && StringTools.startsWith(source,
                "feed:")) {
                sources.set(source.substr(5), true);
            }
            if (block.children != null) {
                used(block.children, document, sources, components);
            }
            if (block.type == "component" && document.components != null
                && !components.exists(block.component)) {
                components.set(block.component, true);
                var component = Reflect.field(document.components, block.component);
                if (component != null) {
                    sections(component.sections, document, sources, components);
                }
            }
        }
    }

    static function sections(entries:Array<Dynamic>, document:Dynamic, sources:Map<String, Bool>,
            components:Map<String, Bool>):Void {
        if (entries == null) {
            return;
        }
        for (section in entries) {
            used(section.blocks, document, sources, components);
        }
    }

    public static function resolve(theme:Dynamic, template:String,
            fallback:String = "Home"):Dynamic {
        var result:Dynamic = {};
        if (theme == null || theme.design == null || theme.design.feeds == null) {
            return result;
        }
        var document = theme.design;
        if (!StringTools.startsWith(template, "@")
            && !Reflect.hasField(document.templates, template)) {
            template = Reflect.hasField(document.templates, fallback) ? fallback : "Home";
        }
        var sources:Map<String, Bool> = [];
        var components:Map<String, Bool> = [];
        if (StringTools.startsWith(template, "@")) {
            var component = Reflect.field(document.components, template.substr(1));
            if (component != null) {
                sections(component.sections, document, sources, components);
            }
        } else {
            sections(document.header, document, sources, components);
            sections(Reflect.field(document.templates, template), document, sources, components);
            sections(document.footer, document, sources, components);
        }
        var feeds:Array<Dynamic> = document.feeds;
        for (feed in feeds) {
            if (!sources.exists(feed.id)) {
                continue;
            }
            var type = ContentTypes.find(feed.collection);
            var rows:Array<Dynamic> = [];
            if (type != null && type.publicVisible) {
                var tag = feed.tag == "" ? null : TagData.named(feed.tag);
                if (feed.tag == "" || tag != null) {
                    var records = ContentQueries.designList(type.key, feed.limit, feed.category,
                        feed.query, tag == null ? 0 : tag.id, feed.order, feed.direction);
                    rows = records.map(record -> ContentItemData.summary(record, type));
                }
            }
            Reflect.setField(result, feed.id, rows);
        }
        return result;
    }
}
