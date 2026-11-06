package hx.press.view;

import hx.press.CategoryData;
import hx.press.i18n.I18n;
import hx.press.media.MediaReferences;

/** The page data the theme builder's interactive canvas reads, as the former page props. */
class DesignCanvas {
    public static function shared(host:ViewHost):Dynamic {
        return ViewData.plain({
            theme: host.root("theme"),
            site: host.root("site"),
            navigation: host.root("navigation"),
            pluginNavigation: host.root("pluginNavigation"),
            extensions: host.root("extensions"),
            themeFeeds: host.root("themeFeeds"),
            primaryArchive: host.root("primaryArchive"),
            mediaRules: MediaReferences.rules(),
            categories: CategoryData.names(),
            i18n: I18n.props()
        });
    }
}
