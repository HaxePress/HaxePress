package hx.press;

import hx.press.media.MediaReferences;
import hx.press.database.DatabaseDate;
import hx.press.data.ContentItemRecord;
import hx.press.data.ContentSummaryRecord;
import hx.press.TagData;
import hx.press.i18n.I18n;
import hx.press.content.ContentTypes;
import hx.press.content.ContentFields;
import hx.press.content.ContentTypeDefinition;

class ContentItemData {
    public static function dateValue(value:Null<DatabaseDate>):String {
        if (value == null) {
            return "";
        }

        return Std.string(value);
    }

    public static function dateLabel(value:Null<DatabaseDate>):String {
        var text = dateValue(value);

        if (text.length < 10) {
            return I18n.t("Not published");
        }

        try {
            var date = Date.fromString(text);
            var month = I18n.t('month.${(date.getMonth() + 1)}');
            var fields:Map<String,
                Dynamic> = ["month" => month, "day" => date.getDate(), "year" => date.getFullYear()];
            return I18n.t("date.short", fields);
        } catch (error:Dynamic) {
            return I18n.t("Not published");
        }
    }

    public static function readingMinutes(content:String):Int {
        var wordCount = content.split(" ").length;
        return Std.int(Math.max(1, Math.ceil(wordCount / 200)));
    }

    public static function summary(item:ContentSummaryRecord, ?type:ContentTypeDefinition):Dynamic {
        if (type == null) {
            type = ContentTypes.find(item.content_type, false);
        }
        var data = presentation(item, type);
        data.fields = type == null ? {} : ContentFields.listValues(item, type, true);
        data.fieldDefinitions = type == null ? [] : [
            for (field in type.fields)
                if (field.inList && field.publicVisible) field
        ];
        return data;
    }

    public static function adminSummary(item:ContentSummaryRecord,
            ?type:ContentTypeDefinition):Dynamic {
        type = type ?? ContentTypes.find(item.content_type, false);
        var data = presentation(item, type);
        data.fields = type == null ? {} : ContentFields.listValues(item, type, false);
        data.adminBase = type == null ? ContentTypes.adminBase(item.content_type) : type.adminBase;
        return data;
    }

    public static function detail(item:ContentItemRecord, publicOnly:Bool = false):Dynamic {
        var type = ContentTypes.find(item.content_type, false);
        var data = presentation(item, type);
        var tags = item.id == 0
            || !ContentTypes.supports(type, "tags") ? [] : TagData.forContent(item.id);
        data.tags = [
            for (tag in tags)
                {
                    id: tag.id,
                    name: tag.name,
                    slug: tag.slug,
                    description: tag.description,
                    url: '/tags/${StringTools.urlEncode(tag.slug)}?type=${StringTools.urlEncode(item.content_type)}'
                }
        ];
        data.fields = type == null ? {} : ContentFields.values(item.id, type, publicOnly);
        data.fieldDefinitions = type == null ? [] : [
            for (field in type.fields)
                if (!publicOnly || field.publicVisible) field
        ];
        if (publicOnly && !ContentTypes.supports(type, "body")) {
            data.content = "";
        }
        if (publicOnly && !ContentTypes.supports(type, "seo")) {
            data.seo_title = "";
            data.seo_description = "";
        }
        return data;
    }

    static function presentation(item:ContentSummaryRecord, ?type:ContentTypeDefinition):Dynamic {
        if (type == null) {
            type = ContentTypes.find(item.content_type, false);
        }
        var data:Dynamic = Reflect.copy(item);
        ContentFields.clearListAliases(data);
        data.url = type == null || !type.publicVisible
            || !type.enabled ? "" : '${type.publicBase}/${StringTools.urlEncode(item.slug)}';
        data.archiveUrl = type != null && type.hasArchive ? type.publicBase : "/";
        data.typeLabel = type == null ? item.content_type : type.singular;
        data.image = MediaReferences.imageUrl(item.image) ? item.image : "";
        if (!ContentTypes.supports(type, "image")) {
            data.image = "";
        }
        if (!ContentTypes.supports(type, "categories")) {
            data.category = "";
        }
        if (!ContentTypes.supports(type, "excerpt")) {
            data.excerpt = "";
        }
        data.showReadingTime = ContentTypes.supports(type, "reading_time");
        data.featured = item.featured == 1;
        data.published_at = dateValue(item.published_at);
        data.updated_at = dateValue(item.updated_at);
        data.publishedLabel = dateLabel(item.published_at);
        data.updatedLabel = dateLabel(item.updated_at);
        data.readMinutes = Std.int(Math.max(1, item.reading_minutes));
        Reflect.deleteField(data, "reading_minutes");
        Reflect.deleteField(data, "created_at");
        return data;
    }
}
