package hx.press.handler.admin.settings;

import hx.press.media.MediaLocks;
import hx.press.media.MediaReferences;
import hx.press.model.MediaAsset;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.AdminController;
import hx.press.ContentCache;
import hx.press.i18n.I18n;
import hx.well.facades.DBStatic;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.auth;
import hx.well.http.ResponseBuilder;
import hx.press.model.Setting;
import hx.press.SiteSettingsStore;
import hx.press.content.ContentTypes;
import hx.press.model.ContentItem;
import hx.well.validator.ValidatorRule;
import hx.well.http.RequestStatic.request;
import hx.press.validation.ValidationResponder;

using StringTools;

class SaveSettingsHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        if (!CmsAccess.can("settings")) {
            return true;
        }
        return request().validate([
            "site_name" => [Required, String, Min(2), Max(100)],
            "publisher_name" => [String, Max(100)],
            "site_logo" => [String, Max(500)],
            "description" => [String, Max(500)],
            "about_site" => [String, Max(1500)],
            "locale" => [String, Max(20)],
            "home_mode" => [String, Max(20)],
            "home_type" => [String, Max(32)],
            "home_page" => [String, Max(16)],
            "home_size" => [String, Max(3)],
            "home_template" => [String, Max(80)]
        ]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return AdminController.settingsForm(request,
            "Check your settings and their length limits.", "", 422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("settings")) {
            return CmsController.forbidden(request);
        }
        var values = request.only("site_name", "publisher_name", "description", "about_site",
            "site_logo", "locale");
        var locale = request.input("locale", I18n.defaultLocale());
        if (!I18n.supported(locale)) {
            return AdminController.settingsForm(request, "Choose a supported language.", "", 422);
        }

        for (key in values.keys()) {
            var value:String = request.input(key, "");
            values.set(key, value.trim());
        }
        values.set("locale", locale);
        var previous = SiteSettingsStore.settings();
        for (key in ["home_mode", "home_type", "home_page", "home_size", "home_template"]) {
            values.set(key, request.input(key, previous.get(key)));
        }
        var mode:String = values.get("home_mode");
        var type = ContentTypes.find(values.get("home_type"));
        var sizeInput:String = values.get("home_size");
        var size = Std.parseInt(sizeInput);
        var template:String = values.get("home_template");
        var pageInput:String = values.get("home_page");
        var page = Std.parseInt(pageInput);
        if (!["collection", "page"].contains(mode)
            || !~/^[0-9]{1,2}$/.match(sizeInput)
            || size == null
            || size < 1
            || size > 24
            || !~/^[A-Za-z][A-Za-z0-9_-]{0,79}$/.match(template)
            || ["ContentDetail", "ContentIndex", "Page", "About", "NotFound"].contains(template)
            || !~/^[0-9]{1,10}$/.match(pageInput)) {
            return AdminController.settingsForm(request,
                "Choose valid homepage and presentation settings.", "", 422);
        }
        if (mode == "collection" && (type == null || !type.publicVisible)) {
            return AdminController.settingsForm(request,
                "Choose an enabled public collection for the homepage.", "", 422);
        }
        if (mode == "page"
            && (page == null
                || !ContentItem.query.where("id", page)
                    .where("status", "published")
                    .whereInQuery("content_type", ContentTypes.publicKeys())
                    .exists())) {
            return AdminController.settingsForm(request,
                "Choose published public content for the homepage.", "", 422);
        }

        var siteName:String = values.get("site_name");
        if (siteName.length < 2) {
            return AdminController.settingsForm(request, "Enter a site name.", "", 422);
        }

        return MediaLocks.run(() -> {
            var logo:String = values.get("site_logo") ?? previous.get("site_logo") ?? "";
            if (logo != "") {
                var filename = logo.substr(MediaReferences.prefix().length);
                var available = MediaReferences.storedImage(logo)
                    && MediaAsset.query.where("filename", filename).exists();
                if (!available) {
                    return AdminController.settingsForm(request,
                        "Choose an existing image from the media library for the site logo.", "",
                        422);
                }
            }
            DBStatic.transaction(() -> {
                for (key => value in values) {
                    Setting.query.upsert(["key" => key, "value" => value], ["key"], ["value"]);
                }
            });

            ContentCache.settingsChanged();
            return ResponseBuilder.asRedirect("/admin/settings?notice=settings", 303);
        });
    }
}
