package extensions.viewcount;

import hx.press.Pagination;
import hx.press.i18n.I18n;
import hx.press.plugins.PluginHost;
import hx.press.view.Pages;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

/** The administration page of the counted views, most viewed first. **/
class ViewCountsPage extends AbstractHandler {
    var host:PluginHost;

    public function new(host:PluginHost) {
        super();
        this.host = host;
    }

    public function execute(request:Request):AbstractResponse {
        if (!host.can(ViewCountPlugin.CAPABILITY)) {
            return ResponseBuilder.asString("Access restricted.", 403);
        }
        var cursor = Pagination.cursor(request);
        var page = ViewCounts.page(cursor, ViewCounts.PAGE_SIZE);
        var total = ViewCounts.count();
        var described = ViewCounts.describe(page.items);
        var rows = [
            for (item in described)
                {
                    id: item.id,
                    title: item.title,
                    collection: I18n.t(item.collection),
                    views: ViewCounts.format(item.views)
                }
        ];
        var links = Pagination.links(ViewCountPlugin.PAGE, new Map(), page, cursor, total,
            record -> record.id, record -> Std.string(record.views));
        var summary = I18n.t("{views} views in total. Counts are updated once a minute.",
            ["views" => ViewCounts.format(ViewCounts.total())], ViewCountPlugin.NAMESPACE);
        var pluginPage = {
            namespace: ViewCountPlugin.NAMESPACE,
            title: "View counts",
            description: summary,
            total: total,
            columns: [
                {
                    key: "title",
                    label: "Content"
                },
                {key: "collection", label: "Collection"},
                {key: "views", label: "Views"}
            ],
            rows: rows,
            actions: [
                {
                    label: "Download JSON",
                    href: '${ViewCountPlugin.PAGE}/data?limit=${ViewCounts.MAX_LIMIT}',
                    download: true
                }
            ],
            pagination: links,
            noun: "counted views"
        };
        var props = {pluginPage: pluginPage};
        return Pages.render("Admin/PluginPage", props);
    }
}
