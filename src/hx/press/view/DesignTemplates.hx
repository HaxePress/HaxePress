package hx.press.view;

/**
    Turns a visual builder document (schema 2) into Wellout templates, one
    page per design template, with the markup the former browser renderer
    produced. Text and attribute values from the document become string
    literals, so the renderer escapes them; links and images are checked
    when they are written. The result is compiled with the policy for
    templates installed at runtime.
**/
class DesignTemplates {
    static inline final MAX_DEPTH = 32;
    static final identifier = ~/^[A-Za-z0-9_-]{1,80}$/;
    static final bindingPath = ~/^(site|item|collection|page)\.[A-Za-z_][A-Za-z0-9_]*$/;
    static inline final CUSTOM_FIELDS = "item.fields.";
    // Custom field keys, as content types define them.
    static final fieldKey = ~/^[a-z][a-z0-9_]{0,31}$/;
    static final siteFields = [
        "locale",
        "site_name",
        "site_logo",
        "publisher_name",
        "description",
        "about_site",
        "home_mode",
        "home_type",
        "home_page",
        "home_size",
        "home_template"
    ];
    static final itemFields = [
        "id",
        "title",
        "slug",
        "excerpt",
        "category",
        "image",
        "image_alt",
        "status",
        "published_at",
        "publishedLabel",
        "updated_at",
        "updatedLabel",
        "readMinutes",
        "content_type",
        "url",
        "archiveUrl",
        "typeLabel",
        "content",
        "seo_title",
        "seo_description"
    ];
    static final collectionFields = ["key", "name", "singular", "description", "publicBase", "hasArchive"];
    static final pageFields = ["count", "resultCount", "query", "category", "archiveUrl"];
    static final templateLabels:Map<String, String> = [
        "Home" => "Homepage",
        "ContentIndex" => "Content archive",
        "ContentDetail" => "Content detail",
        "Page" => "Page",
        "About" => "About",
        "NotFound" => "404 page",
        "header" => "Header",
        "footer" => "Footer"
    ];
    // Fonts bundled with the site, by family name, that a design page preloads for its text.
    static final bundledFonts:Map<String, String> = [
        "DM Sans" => "fonts/dm-sans.woff2",
        "DM Serif Display" => "fonts/dm-serif-display.woff2"
    ];
    static final booleanAttributes = ["required", "disabled", "open", "checked"];
    static final urlAttributes = ["href", "src", "action"];
    static final voidTags = ["input", "br", "hr"];

    final document:Dynamic;
    final output = new StringBuf();
    var scope = "";

    function new(document:Dynamic) {
        this.document = document;
    }

    /** Template sources by name: every design template and every component preview (`@id`). **/
    public static function generate(document:Dynamic):Map<String, String> {
        var sources:Map<String, String> = [];
        if (document == null || document.templates == null) {
            return sources;
        }
        for (name in Reflect.fields(document.templates)) {
            if (identifier.match(name)) {
                sources.set(name, new DesignTemplates(document).page(name));
            }
        }
        return sources;
    }

    /** The CSS custom properties of the design tokens, as a record literal for `cssVariables`. **/
    static function tokens(document:Dynamic):String {
        var tokens:Dynamic = document.tokens == null ? {} : document.tokens;
        var font = designFont(document);
        var entries = [
            'designBackground: ${literal(text(tokens.background))}',
            'designText: ${literal(text(tokens.text))}',
            'designAccent: ${literal(text(tokens.accent))}',
            'designWidth: ${literal('${number(tokens.width)}px')}',
            'designRadius: ${literal('${number(tokens.radius)}px')}',
            'designFont: ${literal(font)}'
        ];
        return '{ ${entries.join(", ")} }';
    }

    /** The design's font stack; the presets `serif` and `sans` name the bundled fonts. **/
    static function designFont(document:Dynamic):String {
        var tokens:Dynamic = document.tokens == null ? {} : document.tokens;
        var font:String = tokens.font == null ? "" : Std.string(tokens.font);
        return switch font {
            case "serif": "'DM Serif Display', Georgia, serif";
            case "sans": "'DM Sans', Arial, sans-serif";
            default: font;
        }
    }

    /**
        A preload for the bundled font the design's text is set in, so the
        first paint does not use a fallback font. Other fonts load as usual.
    **/
    static function fontAsset(document:Dynamic):String {
        var firstFamily = StringTools.trim(designFont(document).split(",")[0]);
        var family = ~/^(['"])(.*)\1$/.replace(firstFamily, "$2");
        var file = bundledFonts.get(family);
        return file == null ? "" : '<Asset font="${file}" />';
    }

    function page(name:String):String {
        scope = name;
        output.add('<props item="ContentItemView?" items="List<ContentItemView> = []" featured="ContentItemView?" related="List<ContentItemView> = []" collection="PublicCollectionView?" pagination="PageLinksView?" query="String = \'\'" category="String = \'\'" archiveUrl="String = \'\'" categories="List<String> = []" fieldFilters="Map<String, String>?" tag="TagView?" count="Int = 0" resultCount="Int = 0" />\n');
        output.add('<Document>\n');
        output.add('<Asset css="css/site.css" /><Asset css="css/cms.css" /><Asset css="css/themes/builder.css" />${fontAsset(document)}\n');
        output.add('<well:head><link rel="stylesheet" href="{{ designStylesheet() }}" /></well:head>\n');
        output.add('<PageHead :title="${pageTitle(name)}" :description="item.seo_description ? item.seo_description : item.excerpt ? item.excerpt : site.description" />\n');
        output.add('<SiteExtensions />\n');
        output.add('<div class="cms-site hp-design" data-cms-site data-layout="builder" style="{{ ${tokens(document)} | cssVariables }}">');
        output.add('<a class="skip-link" href="#main">{{ t(\'Skip to content\') }}</a>');
        output.add('<ExtensionSlot name="site.top" /><header>');
        sections(document.header, "header", 0);
        output.add('</header><main id="main">');
        sections(Reflect.field(document.templates, name), name, 0);
        output.add('</main><ExtensionSlot name="site.before-footer" /><footer>');
        sections(document.footer, "footer", 0);
        output.add('</footer><ExtensionSlot name="site.footer" /></div>\n</Document>\n');
        return output.toString();
    }

    function pageTitle(name:String):String {
        var label = name == "Home" ? "site.site_name" : name == "ContentIndex" ? "collection.name ?? t('Content')" : 't(${literal(templateLabel(name))})';
        return 'item.seo_title ? item.seo_title : item.title ? item.title : ${label}';
    }

    function templateLabel(name:String):String {
        var meta:Dynamic = document.templateMeta == null ? null : Reflect.field(document.templateMeta,
            name);
        if (meta != null && meta.label != null) {
            return Std.string(meta.label);
        }
        var known = templateLabels.get(name);
        return known == null ? name : known;
    }

    function sections(list:Dynamic, owner:String, depth:Int):Void {
        if (list == null || depth > MAX_DEPTH) {
            return;
        }
        var entries:Array<Dynamic> = list;
        for (section in entries) {
            var id = safeId(section.id);
            var align = choice(section.align, ["left", "center", "right"], "left");
            var width = choice(section.width, ["content", "wide", "full"], "content");
            output.add('<section data-design-node="${id}" data-section-id="${id}" data-design-align="${align}" class="hp-design-section${classNames(section.classes)}">');
            if (customLayout(section)) {
                blocks(section.blocks, owner, depth);
            } else {
                var columns = Std.int(Math.max(1, Math.min(12, number(section.columns))));
                output.add('<div class="hp-design-section-inner width-${width}" style="--design-columns: ${columns}">');
                blocks(section.blocks, owner, depth);
                output.add('</div>');
            }
            output.add('</section>');
        }
    }

    static function customLayout(section:Dynamic):Bool {
        var styles:Dynamic = section.styles;
        if (styles == null) {
            return false;
        }
        for (breakpoint in ["desktop", "tablet", "mobile"]) {
            var device:Dynamic = Reflect.field(styles, breakpoint);
            var normal:Dynamic = device == null ? null : device.normal;
            if (normal != null && Reflect.field(normal, "display") != null) {
                return true;
            }
        }
        return false;
    }

    function blocks(list:Dynamic, owner:String, depth:Int):Void {
        if (list == null || depth > MAX_DEPTH) {
            return;
        }
        var entries:Array<Dynamic> = list;
        for (node in entries) {
            block(node, owner, depth);
        }
    }

    /** The attributes every block carries, with its visibility condition. **/
    function common(node:Dynamic, extraClass:String = ""):String {
        var id = safeId(node.id);
        var condition = conditionOf(node);
        var classes = 'hp-design-node${classNames(node.classes)}${extraClass == "" ? "" : ' ${extraClass}'}';
        var conditionAttribute = condition == null ? "" : ' :if="${condition}"';
        return
            '${conditionAttribute} data-design-node="${id}" data-block-id="${id}" class="${classes}"';
    }

    function conditionOf(node:Dynamic):Null<String> {
        var condition:Dynamic = node.condition;
        if (condition == null || condition.field == null || condition.field == "") {
            return null;
        }
        var path = binding(Std.string(condition.field));
        if (path == null) {
            return null;
        }
        return switch Std.string(Reflect.field(condition, "operator")) {
            case "empty": 'not ${path}';
            case "equals": '((${path} ?? \'\') | string) == ${literal(text(condition.value))}';
            default: path;
        }
    }

    /** The template expression for a binding path, or null when it is not a public field. **/
    function binding(path:String):Null<String> {
        var key = customField(path);
        if (key != null) {
            // Item views carry only the custom fields their page may show: public fields on
            // detail pages and public list fields in lists and content sources.
            return 'item.fields[${literal(key)}]';
        }
        if (!bindingPath.match(path)) {
            return null;
        }
        var parts = path.split(".");
        return switch parts[0] {
            case "site" if (siteFields.indexOf(parts[1]) >= 0): 'site.${parts[1]}';
            case "item" if (itemFields.indexOf(parts[1]) >= 0): 'item.${parts[1]}';
            case "collection" if (collectionFields.indexOf(parts[1]) >= 0): 'collection.${parts[1]}';
            case "page" if (pageFields.indexOf(parts[1]) >= 0): parts[1];
            default: null;
        }
    }

    /** The key of an `item.fields.<key>` path, or null for any other path. **/
    static function customField(path:String):Null<String> {
        if (!StringTools.startsWith(path, CUSTOM_FIELDS)) {
            return null;
        }
        var key = path.substr(CUSTOM_FIELDS.length);
        return fieldKey.match(key) ? key : null;
    }

    /** A bound value, or the node's own text, as a template expression. **/
    function value(node:Dynamic, field:String, fallback:String):String {
        var bindings:Dynamic = node.bindings;
        var path:Null<String> = bindings == null ? null : Reflect.field(bindings, field);
        if (path != null && path != "") {
            var bound = binding(path);
            if (bound == null) {
                return "''";
            }
            // Custom field values keep their JSON types; links, images and attributes take text.
            return customField(path) == null ? bound : '(${bound} | string)';
        }
        return literal(fallback);
    }

    function printed(expression:String):String {
        return expression == "''" ? "" : '{{ ${expression} }}';
    }

    function block(node:Dynamic, owner:String, depth:Int):Void {
        if (depth > MAX_DEPTH) {
            return;
        }
        var type = Std.string(node.type);
        var text = value(node, "text", DesignTemplates.text(node.text));
        var href = 'designLink(${value(node, "href", DesignTemplates.text(node.href))})';
        var image = 'designImage(${value(node, "image", DesignTemplates.text(node.image))})';
        var alt = value(node, "alt", DesignTemplates.text(node.alt));
        var children = () -> blocks(node.children, owner, depth + 1);
        switch type {
            case "container":
                output.add('<div${common(node)}>');
                children();
                output.add('</div>');
            case "element":
                element(node, text, href, children);
            case "heading":
                var level = Std.int(Math.max(1, Math.min(6, number(node.level))));
                output.add('<h${level}${common(node)}>');
                var linked = linkGiven(node);
                if (linked) {
                    output.add('<a href="{{ ${href} }}">${printed(text)}</a>');
                } else {
                    output.add(printed(text));
                }
                output.add('</h${level}>');
            case "text":
                output.add('<p${common(node, "hp-design-text")}>${printed(text)}</p>');
            case "image":
                var picture = '<img :if="${image}" class="hp-design-image" src="{{ ${image} }}" alt="{{ ${alt} }}" loading="lazy" />';
                if (linkGiven(node)) {
                    output.add('<a${common(node, "hp-design-image-link")} href="{{ ${href} }}">${picture}</a>');
                } else {
                    output.add('<figure${common(node, "hp-design-image-node")}>${picture}</figure>');
                }
            case "button":
                output.add('<a${common(node, "hp-design-button")} href="{{ ${href} ? ${href} : \'/\' }}">${printed(text)}</a>');
            case "spacer":
                var height = Std.int(Math.max(0, Math.min(64, number(node.level)))) * 16;
                output.add('<div${common(node, "hp-design-spacer")} style="min-height: ${height}px"></div>');
            case "divider":
                output.add('<hr${common(node)} />');
            case "brand":
                output.add('<a${common(node, "hp-design-brand")} href="/"><img :if="site.site_logo" src="{{ site.site_logo }}" alt="{{ site.site_name }}" /><template :else>{{ site.site_name }}</template></a>');
            case "navigation":
                var region = owner == "footer" ? "footer" : "header";
                var label = region == "header" ? "Main navigation" : "Footer navigation";
                output.add('<nav${common(node)} aria-label="{{ t(\'${label}\') }}"><SiteNavigation :links="navigation[\'${region}\'] ?? []" /><a :for="link in pluginNavigation.${region}" href="{{ link.href }}">{{ t(link.label) }}</a></nav>');
            case "site-description":
                var description = scope == "About" ? "site.about_site ? site.about_site : site.description" : "site.description";
                output.add('<p${common(node)}>{{ ${description} }}</p>');
            case "content-title":
                output.add('<h1${common(node)}>{{ item.title }}</h1>');
            case "content-excerpt":
                output.add('<p${common(node, "hp-design-excerpt")}>{{ item.excerpt }}</p>');
            case "content-image":
                output.add('<figure${common(node, "hp-design-image-node")}><img :if="item.image" class="hp-design-image" src="{{ item.image }}" alt="{{ item.image_alt }}" /></figure>');
            case "content-body":
                output.add('<div${common(node, "hp-design-prose")}><ExtensionSlot name="content.before" />{!! markdown(item.content ?? \'\') !!}<FieldValues :definitions="item.fieldDefinitions" :values="item.fields" /><ExtensionSlot name="content.after" /></div>');
            case "repeat":
                output.add('<div${common(node, "hp-design-repeater")}><template :for="item in ${rows(node.source)}">');
                children();
                output.add('</template></div>');
            case "component":
                output.add('<div${common(node, "hp-design-component")}>');
                var component:Dynamic = document.components == null ? null : Reflect.field(document.components,
                    Std.string(node.component));
                if (component != null) {
                    sections(component.sections, owner, depth + 1);
                }
                output.add('</div>');
            case "extension":
                var slot = ~/^[a-z]+(\.[a-z-]+)?$/.match(Std.string(node.slot)) ? Std.string(node.slot) : "site.footer";
                output.add('<div${common(node)}><ExtensionSlot name="${slot}" /></div>');
            case "pagination":
                output.add('<div${common(node)}><Pagination :if="pagination" :links="pagination" :count="size(items)" /></div>');
            case "search":
                output.add('<div${common(node)}>${filters()}</div>');
            case "content-list":
                var list = "(featured or items) ? withFeatured(featured, items) : related";
                output.add('<div${common(node)}>${filters()}<div class="hp-design-content-grid"><article :for="entry in ${list}"><a :if="entry.image" href="{{ entry.url }}" tabindex="-1"><img src="{{ entry.image }}" alt="{{ entry.image_alt }}" loading="lazy" /></a><h2><a href="{{ entry.url }}">{{ entry.title }}</a></h2><p :if="entry.excerpt">{{ entry.excerpt }}</p><time datetime="{{ entry.published_at }}">{{ entry.publishedLabel }}</time></article></div><p :if="not featured and not items and not related">{{ t(\'No content here just yet.\') }}</p><Pagination :if="pagination" :links="pagination" :count="size(items)" />');
                if (scope == "Home") {
                    output.add('<a :if="collection and collection.hasArchive" class="hp-design-archive" href="{{ collection.publicBase }}">{{ t(\'All content\') }}</a>');
                }
                output.add('</div>');
            default:
        }
    }

    static function linkGiven(node:Dynamic):Bool {
        var bindings:Dynamic = node.bindings;
        var bound:Null<String> = bindings == null ? null : Reflect.field(bindings, "href");
        return (bound != null && bound != "") || text(node.href) != "";
    }

    function filters():String {
        return
            '<ContentFilters :if="archiveUrl and collection" :collection="collection" :path="archiveUrl" :query="query" :category="category" :categories="categories" :fieldFilters="fieldFilters" :tag="tag.slug ?? \'\'" />';
    }

    static function rows(source:Dynamic):String {
        var value = source == null ? "page.items" : Std.string(source);
        if (StringTools.startsWith(value, "feed:")) {
            var feed = value.substr(5);
            return identifier.match(feed) ? 'themeFeeds[${literal(feed)}] ?? []' : "[]";
        }
        return value == "page.related" ? "related" : "withFeatured(featured, items)";
    }

    function element(node:Dynamic, text:String, href:String, children:() -> Void):Void {
        var tag = Std.string(node.tag == null ? "div" : node.tag);
        if (!~/^[a-zA-Z][a-zA-Z0-9]{0,30}$/.match(tag)) {
            tag = "div";
        }
        var attributes = new StringBuf();
        var given:Dynamic = node.attributes;
        var hasValue = false;
        if (given != null) {
            for (key in Reflect.fields(given)) {
                if (!~/^[A-Za-z][A-Za-z0-9:_-]{0,40}$/.match(key)
                    || key == "class"
                    || key == "style"
                    || StringTools.startsWith(key.toLowerCase(), "on")) {
                    continue;
                }
                var raw = DesignTemplates.text(Reflect.field(given, key));
                var name = key == "htmlFor" ? "for" : key == "dateTime" ? "datetime" : key;
                if (name == "value") {
                    hasValue = true;
                    continue;
                }
                if (name == "datetime") {
                    continue;
                }
                if (booleanAttributes.indexOf(name) >= 0) {
                    if (raw != "false" && raw != "0") {
                        attributes.add(' ${name}');
                    }
                    continue;
                }
                if (tag == "a" && name == "href") {
                    continue;
                }
                attributes.add(' ${name}="{{ ${literal(raw)} }}"');
            }
        }
        var bindings:Dynamic = node.bindings;
        if (hasValue || (bindings != null && Reflect.field(bindings, "value") != null)) {
            var fallback = given == null ? "" : DesignTemplates.text(Reflect.field(given, "value"));
            attributes.add(' value="{{ ${value(node, "value", fallback)} }}"');
        }
        var datetimeFallback = given == null ? "" : DesignTemplates.text(Reflect.field(given,
            "datetime") ?? Reflect.field(given, "dateTime"));
        var datetime = value(node, "datetime", datetimeFallback);
        if (datetime != "''") {
            attributes.add(' datetime="{{ ${datetime} }}"');
        }
        if (tag == "a") {
            attributes.add(' href="{{ ${href} ? ${href} : \'/\' }}"');
        }
        if (voidTags.indexOf(tag) >= 0) {
            output.add('<${tag}${attributes.toString()}${common(node)} />');
            return;
        }
        output.add('<${tag}${attributes.toString()}${common(node)}>');
        output.add(printed(text));
        children();
        output.add('</${tag}>');
    }

    static function classNames(value:Dynamic):String {
        if (value == null || !Std.isOfType(value, Array)) {
            return "";
        }
        var names:Array<Dynamic> = value;
        var output = new StringBuf();
        for (name in names) {
            var text = Std.string(name);
            if (identifier.match(text)) {
                output.add(' ${text} design-class-${text}');
            }
        }
        return output.toString();
    }

    static function safeId(value:Dynamic):String {
        var text = value == null ? "" : Std.string(value);
        return identifier.match(text) ? text : "node";
    }

    static function choice(value:Dynamic, options:Array<String>, fallback:String):String {
        var text = value == null ? "" : Std.string(value);
        return options.indexOf(text) >= 0 ? text : fallback;
    }

    static function text(value:Dynamic):String {
        return value == null ? "" : Std.string(value);
    }

    static function number(value:Dynamic):Float {
        if (value == null) {
            return 0;
        }
        var parsed = Std.parseFloat(Std.string(value));
        return Math.isFinite(parsed) ? parsed : 0;
    }

    /** A Wellout string literal: the renderer escapes it when it is written. **/
    public static function literal(value:String):String {
        var escaped = StringTools.replace(value, "\\", "\\\\");
        escaped = StringTools.replace(escaped, "'", "\\'");
        escaped = StringTools.replace(escaped, "\n", "\\n");
        escaped = StringTools.replace(escaped, "\r", "\\r");
        escaped = StringTools.replace(escaped, "\t", "\\t");
        // Literals sit inside double-quoted attributes, so a double quote is escaped as a code point.
        escaped = StringTools.replace(escaped, '"', "\\u0022");
        return '\'${escaped}\'';
    }
}
