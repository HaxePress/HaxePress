package hx.press.handler.admin.navigation;

import hx.press.i18n.SiteTexts;
import hx.press.i18n.Languages;
import hx.press.content.ContentLocks;
import hx.press.Activity;
import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.ContentCache;
import hx.press.ManagementController;
import hx.press.SiteController;
import hx.press.SiteSettingsStore;
import hx.press.content.ContentTypes;
import hx.press.media.MediaLocks;
import hx.press.model.ContentItem;
import hx.press.model.MenuLink;
import hx.press.navigation.NavigationRegions;
import hx.press.validation.Flag;
import hx.press.validation.ValidationResponder;
import hx.well.facades.DBStatic;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;
#if jvm
import java.net.URI;
#end

/** Saves a navigation link, which can show in every language or in one. **/
class SaveNavigationHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        var current = request();
        if (!CmsAccess.can("navigation")) {
            return true;
        }
        return
            current.validate(["label" => [Required, String, Min(1), Max(80)], "url" => [String, Max(1000)]]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return ManagementController.navigation(request,
            "Choose a label, menu location and a position from 0 to 9999.", 422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("navigation")) {
            return CmsController.forbidden(request);
        }
        return ContentLocks.run("navigation", () -> persistNavigation(request));
    }

    static function persistNavigation(request:Request):AbstractResponse {
        var id = Std.parseInt(AdminController.input(request, "id", 16)) ?? 0;
        var location = AdminController.input(request, "location", 41);
        var region = NavigationRegions.find(location);
        var label = AdminController.input(request, "label", 100);
        var url = AdminController.input(request, "url", 1000);
        var position = Std.parseInt(AdminController.input(request, "position", 5));
        var contentId = Std.parseInt(AdminController.input(request, "content_id", 16)) ?? 0;

        if (label == "" || region == null || position == null || position < 0 || position > 9999) {
            return ManagementController.navigation(request,
                "Choose a label, menu location and a position from 0 to 9999.", 422);
        }
        var collectionKey = AdminController.input(request, "collection_key", 33);
        if (contentId > 0 && collectionKey != "") {
            return ManagementController.navigation(request,
                "Choose a content item or a collection for this link.", 422);
        }
        if (contentId > 0) {
            var content = ContentItem.query.select(["slug", "content_type"])
                .where("id", contentId)
                .where("status", "published")
                .whereInQuery("content_type", ContentTypes.publicKeys())
                .limit(1)
                .first();
            if (content == null) {
                return ManagementController.navigation(request,
                    "Choose published public content for this link.", 422);
            }
            url = ContentTypes.url(content.content_type, content.slug);
        }
        if (collectionKey != "") {
            var collection = ContentTypes.find(collectionKey);
            if (collection == null || !collection.publicVisible || !collection.hasArchive) {
                return ManagementController.navigation(request,
                    "Choose an enabled public collection with an archive.", 422);
            }
            url = collection.publicBase;
        }
        if (!safeUrl(url)) {
            return ManagementController.navigation(request,
                "Use a relative site path or a complete HTTP/HTTPS URL.", 422);
        }
        var existing = id == 0 ? null : MenuLink.query.select(["id", "location"])
            .where("id", id)
            .limit(1)
            .first();
        if (id > 0 && existing == null) {
            return SiteController.notFound(request);
        }
        if ((existing == null || existing.location != location)
            && MenuLink.query.where("location", location).count() >= region.max_links) {
            return ManagementController.navigation(request,
                "This navigation region has reached its link limit.", 422);
        }
        var values:Map<String, Dynamic> = [
            "label" => label,
            "url" => url,
            "location" => location,
            "position" => position,
            "content_id" => contentId,
            "collection_key" => collectionKey,
            "language" => linkLanguage(request),
            "new_tab" => Flag.input(request, "new_tab") ? 1 : 0,
            "updated_at" => SiteSettingsStore.timestamp()
        ];
        MediaLocks.run(() -> {
            DBStatic.transaction(() -> {
                var savedId = id;
                if (existing == null) {
                    values.set("created_at", SiteSettingsStore.timestamp());
                    savedId = MenuLink.query.insert(values);
                } else {
                    existing.update(values);
                }
                Activity.record("saved", "navigation", savedId, label);
                SiteTexts.put('menu.${savedId}.label', "menu", label);
            });
            return true;
        });
        ContentCache.changed("navigation");
        return ResponseBuilder.asRedirect('/admin/navigation?location=${location}&notice=saved',
            303);
    }

    static function safeUrl(value:String):Bool {
        if (StringTools.startsWith(value, "/") && !StringTools.startsWith(value, "//")) {
            return value.indexOf("\\") < 0 && !~/[\x00-\x20]/.match(value);
        }
        #if jvm
        try {
            var uri = new URI(value);
            return ["https", "http"].contains(uri.getScheme()) && uri.getHost() != null
                && uri.getUserInfo() == null;
        } catch (invalid:Dynamic) {
            return false;
        }
        #else
        // The rules java.net.URI applies on the JVM: an http or https address
        // with a host name or IP address, no user information and no spaces.
        var absoluteUrl = ~/^https?:\/\/(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\.?|\[[0-9A-Fa-f:.]+\])(?::[0-9]*)?(?:[\/?#][^\x00-\x20"<>\\^`{|}]*)?$/;
        return absoluteUrl.match(value);
        #end
    }

    /** The one language a link is shown in, or "" for every language. **/
    static function linkLanguage(request:Request):String {
        var language = AdminController.input(request, "language", 35);
        return Languages.exists(language) && Languages.prefixed() ? language : "";
    }
}
