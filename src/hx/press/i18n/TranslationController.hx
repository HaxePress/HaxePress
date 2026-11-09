package hx.press.i18n;

import haxe.Json;
import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.Pagination;
import hx.press.SiteController;
import hx.press.i18n.TranslationHub.HubFilter;
import hx.press.i18n.TranslationHub.HubInput;
import hx.press.i18n.TranslationHub.HubTextRow;
import hx.press.i18n.TranslationHub.HubTranslationRow;
import hx.press.validation.PositiveInt;
import hx.press.view.View;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.well.http.StringResponse;

using StringTools;

/**
    The Translations page: every text of the CMS, the themes, the plugins
    and the site, with what each language shows and the translations made
    on this site. The MCP translation tools call the same routes.
**/
class TranslationController {
    static inline var URL = "/admin/translations";

    static function allowed():Bool {
        return CmsAccess.can("translations");
    }

    static function adminId():Int {
        var admin = CmsAccess.current();
        return admin == null ? 0 : admin.id;
    }

    /** The language a request names, or the first language that needs translations. **/
    static function languageOf(request:Request):String {
        var requested = AdminController.input(request, "language", 35);
        if (requested == "") {
            requested = request.query("language", "");
        }
        if (TranslationHub.languages().contains(requested)) {
            return requested;
        }
        for (language in Languages.all()) {
            if (language.is_default != 1) {
                return language.code;
            }
        }
        return Languages.defaultCode();
    }

    static function filterOf(request:Request):HubFilter {
        var source = request.query("source", "");
        var status = request.query("status", "all");
        var audience = request.query("audience", "site");
        return {
            language: languageOf(request),
            source: TranslationHub.validSource(source) ? source : "",
            status: TranslationHub.statuses.contains(status) ? status : "all",
            audience: TranslationHub.audiences.contains(audience) ? audience : "site",
            query: request.query("q", "").trim().substr(0, 80)
        };
    }

    /** The page's own address with its query, without a notice. **/
    static function currentUrl(request:Request):String {
        var pairs:Array<String> = [];
        for (key => value in request.queries) {
            if (key != "notice") {
                pairs.push('${StringTools.urlEncode(key)}=${StringTools.urlEncode(value)}');
            }
        }
        return pairs.length == 0 ? request.path : '${request.path}?${pairs.join("&")}';
    }

    static function sourceName(namespace:String):String {
        if (namespace == "cms") {
            return "HaxePress";
        }
        if (namespace == "site") {
            return I18n.t("Site");
        }
        for (item in TranslationHub.packages()) {
            if (item.id == namespace) {
                return I18n.installedT(item.name, null, item.id);
            }
        }
        return namespace;
    }

    static function item(text:HubTextRow, translation:Null<HubTranslationRow>,
            language:String):Dynamic {
        var source = TranslationHub.forms(text, text.source);
        var shipped = TranslationHub.forms(text, translation == null ? "" : translation.shipped);
        var value = TranslationHub.forms(text, translation == null ? "" : translation.value);
        var plural = text.plural == 1;
        return {
            id: text.id,
            namespace: text.namespace,
            sourceName: sourceName(text.namespace),
            key: text.key,
            origin: text.origin,
            audience: text.audience,
            plural: plural,
            sourceLanguage: text.language,
            source: plural ? "" : source[0],
            sourceOne: plural ? source[0] : "",
            sourceOther: plural ? source[source.length - 1] : "",
            placeholders: [for (name in TranslationHub.placeholders(text.source)) '{${name}}'],
            shipped: plural ? "" : shipped[0],
            shippedOne: plural ? shipped[0] : "",
            shippedOther: plural ? shipped[shipped.length - 1] : "",
            shippedText: shipped[0] == "" ? "" : plural ? '${shipped[0]} / ${shipped[shipped.length - 1]}' : shipped[0],
            value: plural ? "" : value[0],
            valueOne: plural ? value[0] : "",
            valueOther: plural ? value[value.length - 1] : "",
            effective: TranslationHub.effective(text, translation),
            status: TranslationHub.status(text, translation, language),
            outdated: translation != null && translation.outdated == 1,
            sourceEditable: text.namespace == "site" && text.language == language};
    }

    static function sourceChoices():Array<Dynamic> {
        var choices:Array<Dynamic> = [
            {value: "", label: I18n.t("Every source")},
            {value: "core", label: "HaxePress"},
            {value: "site", label: I18n.t("Site")},
            {value: "themes", label: I18n.t("Themes")},
            {value: "plugins", label: I18n.t("Plugins")}
        ];
        for (item in TranslationHub.packages()) {
            choices.push({value: item.id, label: I18n.installedT(item.name, null, item.id)});
        }
        return choices;
    }

    public static function index(request:Request):AbstractResponse {
        return page(request, "", 200);
    }

    static function page(request:Request, error:String, status:Int):AbstractResponse {
        if (!allowed()) {
            return CmsController.forbidden(request);
        }
        var redirect = AdminController.validationRedirect(request, "translations", error,
            currentUrl(request));
        if (redirect != null) {
            return redirect;
        }
        var filter = filterOf(request);
        var cursor = Pagination.cursor(request);
        var result = TranslationHub.page(filter, cursor);
        var total = TranslationHub.count(filter);
        var parameters = [
            "language" => filter.language,
            "source" => filter.source,
            "status" => filter.status == "all" ? "" : filter.status,
            "audience" => filter.audience == "site" ? "" : filter.audience,
            "q" => filter.query
        ];
        var links = Pagination.links(URL, parameters, result, cursor, total, text -> text.id,
            text -> null);
        var states = TranslationHub.translationsOf([for (text in result.items) text.id],
            filter.language);
        var items = [
            for (text in result.items)
                item(text, states.get(text.id), filter.language)
        ];
        var languages:Array<Dynamic> = [];
        for (language in Languages.all()) {
            var counts = TranslationHub.progress(language.code, filter.source, filter.audience);
            var percent = counts.total == 0 ? 100 : Math.floor(counts.translated * 100 / counts.total);
            languages.push({
                code: language.code,
                name: language.name,
                isDefault: language.is_default == 1,
                enabled: language.enabled == 1,
                total: counts.total,
                translated: counts.translated,
                edited: counts.edited,
                review: counts.review,
                missing: counts.total - counts.translated,
                percent: percent,
                href: '${URL}?language=${StringTools.urlEncode(language.code)}&source=${StringTools.urlEncode(filter.source)}'
            });
        }
        var notice = switch (request.query("notice", "")) {
            case "saved": "The translations have been saved.";
            case "removed": "The site’s translation has been removed.";
            case "imported": "The translations have been imported.";
            case "rescanned": "The texts of the CMS, themes and plugins have been listed again.";
            default: "";
        };
        var props:Map<String, Dynamic> = [
            "notice" => notice,
            "filter" => filter,
            "progress" => languages,
            "sources" => sourceChoices(),
            "items" => items,
            "pagination" => links,
            "single" => Languages.all().length == 1,
            "canRescan" => CmsAccess.can("extensions"),
            "returnTo" => currentUrl(request),
            "ids" => [for (text in result.items) Std.string(text.id)].join(",")
        ];
        if (error != "") {
            props.set("errors", ["translations" => error]);
        }
        return View.render("Admin/Translations", props).status(status);
    }

    public static function show(request:Request):AbstractResponse {
        if (!allowed()) {
            return CmsController.forbidden(request);
        }
        var id = PositiveInt.parse(request.route("id"));
        var text = id == null ? null : TranslationHub.text(id);
        if (text == null) {
            return SiteController.notFound(request);
        }
        var stored:Map<String, HubTranslationRow> = [];
        for (translation in TranslationHub.allTranslations(text.id)) {
            stored.set(translation.language, translation);
        }
        var translations = [
            for (language in Languages.all())
                {
                    language: language.code,
                    name: language.name,
                    enabled: language.enabled == 1,
                    translation: item(text, stored.get(language.code), language.code)
                }
        ];
        return View.render("Admin/TranslationText", {
            text: item(text, null, text.language),
            entries: translations,
            returnTo: currentUrl(request)
        });
    }

    static function inputOf(request:Request, suffix:String):HubInput {
        var field = (name:String) -> {
            var value:Dynamic = request.input('${name}${suffix}', null);
            return Std.isOfType(value, String) ? (value : String) : null;
        };
        return {value: field("value"), one: field("one"), other: field("other")};
    }

    static function done(request:Request, notice:String, data:Dynamic):AbstractResponse {
        if (View.isDataRequest(request)) {
            return ResponseBuilder.asJson(data);
        }
        return ResponseBuilder.asRedirect(withNotice(returnPath(request), notice), 303);
    }

    static function failed(request:Request, error:String, ?details:Dynamic):AbstractResponse {
        if (View.isDataRequest(request)) {
            return ResponseBuilder.asJson({error: I18n.t(error), errors: details}, 422);
        }
        View.flash("errors", ["translations" => error]);
        return ResponseBuilder.asRedirect(returnPath(request), 303);
    }

    static function returnPath(request:Request):String {
        var target = AdminController.input(request, "return_to", 2000);
        var unsafe = ~/[\x00-\x20\\]/;
        if (!(target == URL || target.startsWith('${URL}?') || target.startsWith('${URL}/'))
            || unsafe.match(target)) {
            return URL;
        }
        return target;
    }

    static function withNotice(path:String, notice:String):String {
        var pattern = ~/([?&])notice=[^&]*&?/;
        var clean = pattern.replace(path, "$1");
        if (clean.endsWith("?") || clean.endsWith("&")) {
            clean = clean.substr(0, clean.length - 1);
        }
        return '${clean}${clean.indexOf("?") >= 0 ? "&" : "?"}notice=${notice}';
    }

    /** Saves one translation. **/
    public static function save(request:Request):AbstractResponse {
        if (!allowed()) {
            return CmsController.forbidden(request);
        }
        var id = PositiveInt.parse(AdminController.input(request, "text_id", 12));
        var text = id == null ? null : TranslationHub.text(id);
        if (text == null) {
            return failed(request, "This text does not exist.");
        }
        var language = AdminController.input(request, "language", 35);
        var result = TranslationHub.save(text, language, inputOf(request, ""), adminId());
        if (result.error != null) {
            var details:Dynamic = text.namespace == "site" ? {editPath: SiteTexts.editPath(text.key)} : null;
            return failed(request, result.error, details);
        }
        return done(request, "saved", result.saved);
    }

    /**
        Saves the translations of a page into one language. The page posts
        `value_{id}` fields for the listed `ids`, or `only`/`remove` for one
        row; MCP posts `items` as JSON.
    **/
    public static function saveBatch(request:Request):AbstractResponse {
        if (!allowed()) {
            return CmsController.forbidden(request);
        }
        var language = AdminController.input(request, "language", 35);
        var removed = PositiveInt.parse(AdminController.input(request, "remove", 12));
        if (removed != null) {
            var text = TranslationHub.text(removed);
            if (text == null || !TranslationHub.languages().contains(language)) {
                return failed(request, "This text does not exist.");
            }
            return done(request, "removed", TranslationHub.remove(text, language));
        }
        var items:Array<{id:Int, input:HubInput}> = [];
        var posted = AdminController.input(request, "items", 1000000);
        if (posted != "") {
            var parsed:Dynamic = try Json.parse(posted) catch (error:Dynamic) null;
            if (!Std.isOfType(parsed, Array)) {
                return failed(request, "Send the translations as a list.");
            }
            var list:Array<Dynamic> = parsed;
            for (entry in list) {
                var id:Dynamic = entry.id;
                if (!Std.isOfType(id, Int)) {
                    return failed(request, "Every translation needs the id of its text.");
                }
                items.push({
                    id: id,
                    input: {
                        value: Std.isOfType(entry.value, String) ? entry.value : null,
                        one: Std.isOfType(entry.one, String) ? entry.one : null,
                        other: Std.isOfType(entry.other, String) ? entry.other : null
                    }
                });
            }
        } else {
            var only = PositiveInt.parse(AdminController.input(request, "only", 12));
            var ids = AdminController.input(request, "ids", 20000).split(",");
            for (raw in ids) {
                var id = PositiveInt.parse(raw.trim());
                if (id == null || (only != null && id != only)) {
                    continue;
                }
                var input = inputOf(request, '_${id}');
                var empty = (input.value ?? "").trim() == ""
                    && (input.one ?? "").trim() == "" && (input.other ?? "").trim() == "";
                // Rows left empty or unchanged are not translations of this page.
                if (!empty && changed(request, id, input)) {
                    if (input.value == null || input.value == "") {
                        input.value = null;
                    } else {
                        input.one = null;
                        input.other = null;
                    }
                    items.push({id: id, input: input});
                }
            }
        }
        if (items.length > TranslationHub.MAX_BATCH) {
            return failed(request, "Save at most 100 translations at a time.");
        }
        var result = TranslationHub.saveMany(language, items, adminId());
        if (!View.isDataRequest(request) && result.failed.length > 0) {
            return failed(request, result.failed[0].error);
        }
        return done(request, "saved",
            {language: language, saved: result.saved, failed: result.failed});
    }

    /** Whether a page row differs from the translation it was shown with. **/
    static function changed(request:Request, id:Int, input:HubInput):Bool {
        var original = AdminController.input(request, 'original_${id}', 20000);
        var current = input.value ?? '${input.one ?? ""}\n${input.other ?? ""}';
        return current.replace("\r\n", "\n") != original.replace("\r\n", "\n");
    }

    public static function remove(request:Request):AbstractResponse {
        if (!allowed()) {
            return CmsController.forbidden(request);
        }
        var id = PositiveInt.parse(AdminController.input(request, "text_id", 12));
        var text = id == null ? null : TranslationHub.text(id);
        var language = AdminController.input(request, "language", 35);
        if (text == null || !TranslationHub.languages().contains(language)) {
            return failed(request, "This text does not exist.");
        }
        return done(request, "removed", TranslationHub.remove(text, language));
    }

    public static function progress(request:Request):AbstractResponse {
        if (!allowed()) {
            return CmsController.forbidden(request);
        }
        var filter = filterOf(request);
        var languages:Array<Dynamic> = [];
        for (language in Languages.all()) {
            var counts = TranslationHub.progress(language.code, filter.source, filter.audience);
            languages.push({
                code: language.code,
                name: language.name,
                isDefault: language.is_default == 1,
                enabled: language.enabled == 1,
                total: counts.total,
                translated: counts.translated,
                missing: counts.total - counts.translated,
                edited: counts.edited,
                review: counts.review
            });
        }
        return ResponseBuilder.asJson({
            defaultLanguage: Languages.defaultCode(),
            source: filter.source,
            audience: filter.audience,
            languages: languages
        });
    }

    public static function sources(request:Request):AbstractResponse {
        if (!allowed()) {
            return CmsController.forbidden(request);
        }
        var sources:Array<Dynamic> = [
            {
                source: "core",
                label: "HaxePress",
                kind: "core",
                active: true
            },
            {
                source: "site",
                label: I18n.t("Site"),
                kind: "site",
                active: true
            }
        ];
        for (item in TranslationHub.packages()) {
            sources.push({
                source: item.id,
                label: I18n.installedT(item.name, null, item.id),
                kind: item.kind,
                active: item.enabled
            });
        }
        return ResponseBuilder.asJson({sources: sources});
    }

    /** The namespace of a single source, or null. **/
    static function namespaceOf(source:String):Null<String> {
        if (source == "core") {
            return "cms";
        }
        if (source == "site") {
            return "site";
        }
        return Lambda.exists(TranslationHub.packages(), item -> item.id == source) ? source : null;
    }

    public static function export(request:Request):AbstractResponse {
        if (!allowed()) {
            return CmsController.forbidden(request);
        }
        var namespace = namespaceOf(request.query("source", ""));
        var language = request.query("language", "");
        var include = request.query("include", "effective");
        if (namespace == null || !TranslationHub.languages().contains(language)
            || !["effective", "site", "missing"].contains(include)) {
            return failed(request,
                "Choose a source, one of the site’s languages and what to export.");
        }
        var after = PositiveInt.parse(request.query("cursor", "")) ?? 0;
        var page = TranslationHub.exportPage(namespace, language, include, after);
        return ResponseBuilder.asJson({
            source: request.query("source", ""),
            language: language,
            include: include,
            messages: ViewDataPlain.messages(page.messages),
            nextCursor: page.next == 0 ? "" : '${page.next}',
            complete: page.next == 0
        });
    }

    /** The whole catalogue of a source in one language, as a file. **/
    public static function download(request:Request):AbstractResponse {
        if (!allowed()) {
            return CmsController.forbidden(request);
        }
        var source = request.query("source", "");
        var namespace = namespaceOf(source);
        var language = request.query("language", "");
        var include = request.query("include", "effective");
        if (namespace == null || !TranslationHub.languages().contains(language)
            || !["effective", "site", "missing"].contains(include)) {
            return SiteController.notFound(request);
        }
        var messages:Map<String, Dynamic> = [];
        var after = 0;
        do {
            var page = TranslationHub.exportPage(namespace, language, include, after);
            for (key => message in page.messages) {
                messages.set(key, message);
            }
            after = page.next;
        } while (after != 0);
        var body = Json.stringify(ViewDataPlain.messages(messages), null, "  ");
        var response = new StringResponse(body, 200);
        var name = '${source == "" ? "translations" : source}-${language}.json';
        response.header("Content-Type", "application/json; charset=utf-8");
        response.header("Content-Disposition", 'attachment; filename="${name}"');
        return response;
    }

    public static function importCatalogue(request:Request):AbstractResponse {
        if (!allowed()) {
            return CmsController.forbidden(request);
        }
        var namespace = namespaceOf(AdminController.input(request, "source", 100));
        var language = AdminController.input(request, "language", 35);
        var mode = AdminController.input(request, "mode", 20);
        if (mode == "") {
            mode = "missing";
        }
        if (namespace == null || !TranslationHub.languages().contains(language)
            || !["missing", "overwrite"].contains(mode)) {
            return failed(request,
                "Choose a source, one of the site’s languages and how to import.");
        }
        var messages:Map<String, Dynamic>;
        try {
            messages = TranslationCatalogue.parse(AdminController.input(request, "catalogue",
                TranslationCatalogue.MAX_BYTES + 1));
        } catch (error:Dynamic) {
            return failed(request,
                "Import a catalogue: a JSON object of texts, within 128 KB and 1500 texts.");
        }
        var keys = [for (key in messages.keys()) key];
        var found = TranslationHub.byKeys(namespace, keys);
        var existing = TranslationHub.translationsOf([for (text in found) text.id], language);
        var items:Array<{id:Int, input:HubInput}> = [];
        var unknown:Array<String> = [];
        var skipped = 0;
        for (key in keys) {
            var text = found.get(key);
            if (text == null) {
                unknown.push(key);
                continue;
            }
            var translation = existing.get(text.id);
            var translatedAlready = translation != null
                && (translation.value != "" || translation.shipped != "");
            if (mode == "missing" && translatedAlready) {
                skipped++;
                continue;
            }
            var message:Dynamic = messages.get(key);
            items.push({
                id: text.id,
                input: Std.isOfType(message, String) ? {value: message, one: null, other: null} : {
                    value: null,
                    one: message.one,
                    other: message.other
                }
            });
        }
        var imported = 0;
        var invalid:Array<{key:String, error:String}> = [];
        var index = 0;
        var byId = [for (key => text in found) text.id => key];
        while (index < items.length) {
            var batch = items.slice(index, index + TranslationHub.MAX_BATCH);
            index += TranslationHub.MAX_BATCH;
            var result = TranslationHub.saveMany(language, batch, adminId());
            imported += result.saved.length;
            for (failure in result.failed) {
                if (invalid.length < 50) {
                    invalid.push({key: byId.get(failure.id), error: failure.error});
                }
            }
        }
        return done(request, "imported", {
            imported: imported,
            skipped: skipped,
            unknownKeys: unknown.slice(0, 50),
            unknownCount: unknown.length,
            invalid: invalid
        });
    }

    public static function rescan(request:Request):AbstractResponse {
        if (!allowed() || !CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        TranslationSync.core(true);
        var count = 1;
        for (item in TranslationHub.packages()) {
            TranslationSync.forPackage(item.id);
            count++;
        }
        return done(request, "rescanned", {namespaces: count});
    }
}

/** Catalogue messages as plain JSON values, which PHP writes as objects. **/
private class ViewDataPlain {
    public static function messages(messages:Map<String, Dynamic>):Dynamic {
        var plain:Dynamic = {};
        var keys = [for (key in messages.keys()) key];
        keys.sort(Reflect.compare);
        for (key in keys) {
            Reflect.setField(plain, key, messages.get(key));
        }
        return plain;
    }
}
