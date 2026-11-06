package hx.press.view;

import haxe.crypto.Base64;
import hx.press.i18n.I18n;
import hx.press.i18n.TranslationCatalogue;
import hx.well.http.Request;
import hx.well.internal.SecureToken;
import wellout.check.CheckedTemplate.AssetKind;
import wellout.render.RenderHost;

/**
    The Wellout host for one HaxePress response: implicit roots, the
    translation namespace, CSRF token, CSP nonce, asset URLs and, inside
    theme previews, the link mapper.
**/
class ViewHost implements RenderHost {
    public final request:Null<Request>;
    public final props:Dynamic;

    /** The translation namespace: `cms`, or the package id for theme and plugin templates. **/
    public final namespace:String;

    /** The public base of a package's assets, or null for application templates. **/
    public final packageAssetBase:Null<String>;

    final mapper:Null<String->String>;
    final islands:Null<Map<String, String>>;
    final values:Map<String, Dynamic> = [];
    var nonceValue:Null<String> = null;
    var coreMessages:Null<Map<String, Dynamic>> = null;
    var ownMessages:Null<Map<String, Dynamic>> = null;
    var locale:Null<String> = null;

    public function new(request:Null<Request>, props:Dynamic, namespace:String,
            ?packageAssetBase:String, ?mapper:String->String, ?islands:Map<String, String>) {
        this.request = request;
        this.props = props;
        this.namespace = namespace;
        this.packageAssetBase = packageAssetBase;
        this.mapper = mapper;
        this.islands = islands;
    }

    public function root(name:String):Dynamic {
        if (values.exists(name)) {
            return values.get(name);
        }
        var value = ViewRoots.resolve(name, this);
        values.set(name, value);
        return value;
    }

    public function linkMapper():Null<String->String> {
        return mapper;
    }

    public function csrfToken():String {
        var shared = View.shared(request);
        if (shared != null && shared.exists("csrfToken")) {
            // A preview shares no token, so the forms of its theme templates carry none either.
            var sharedToken:Null<String> = shared.get("csrfToken");
            return sharedToken == null ? "" : sharedToken;
        }
        var token:Null<String> = request == null
            || request.session == null ? null : request.session.get("_token");
        return token == null ? "" : token;
    }

    public function nonce():String {
        if (nonceValue == null) {
            nonceValue = request == null ? SecureToken.generate(22) : View.nonce(request);
        }
        return nonceValue;
    }

    /** `<Asset>` names application assets; theme templates link their own files with `themeAsset()`. **/
    public function assetUrl(kind:AssetKind, path:String):String {
        return ViewAssets.url('resources/${path}');
    }

    /**
        A plugin's islands load from its package; the application's are built
        from `resources/js/islands/<name>.tsx`, or `.ts` when they use no JSX.
    **/
    public function islandModule(name:String):String {
        var packaged = islands == null ? null : islands.get(name);
        if (packaged != null) {
            return packaged;
        }
        var react = ViewAssets.url('resources/js/islands/${name}.tsx');
        return react != "" ? react : ViewAssets.url('resources/js/islands/${name}.ts');
    }

    public function translate(key:String):String {
        return t(key, null);
    }

    public function runtimeScript():String {
        return WelloutClient.url();
    }

    /** Translates with the template's namespace first, then the CMS catalogue. **/
    public function t(key:String, parameters:Null<Map<String, Dynamic>>):String {
        return TranslationCatalogue.format(message(key), key, parameters);
    }

    public function message(key:String):Dynamic {
        if (locale == null) {
            locale = I18n.locale();
            coreMessages = I18n.coreMessages(locale);
            // Administration pages, such as the preview of an inactive theme, read installed
            // packages' catalogues; public pages only enabled ones.
            ownMessages = namespace == "cms" ? null : ViewRoots.isAdmin(request) ? I18n.installedMessages(namespace,
                locale) : I18n.namespaceMessages(namespace, locale);
        }
        if (ownMessages != null) {
            var own = ownMessages.get(key);
            if (own != null) {
                return own;
            }
        }
        return coreMessages.get(key);
    }
}
