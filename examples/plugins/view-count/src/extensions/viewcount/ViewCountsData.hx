package extensions.viewcount;

import hx.press.Pagination;
import hx.press.i18n.I18n;
import hx.press.plugins.PluginHost;
import hx.press.validation.PositiveInt;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

/**
    The counted views as JSON, most viewed first, for scripts and the
    plugin's MCP tool: `content` reads one content item, `cursor` continues
    a list and `limit` sets its length, at most 100.
**/
class ViewCountsData extends AbstractHandler implements ValidationResponder {
    var host:PluginHost;

    public function new(host:PluginHost) {
        super();
        this.host = host;
    }

    public override function validate():Bool {
        return request().validate([
            "content" => [Custom("cms.positive_int")],
            "limit" => [Custom("cms.positive_int", [ViewCounts.MAX_LIMIT])],
            "cursor" => [String, Max(512)]
        ]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        var error = I18n.t("Use a content ID, a cursor from a previous answer and a limit of at most 100.",
            null,
            ViewCountPlugin.NAMESPACE);
        return ResponseBuilder.asJson({error: error}, 422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!host.can(ViewCountPlugin.CAPABILITY)) {
            return ResponseBuilder.asJson({error: "Access restricted."}, 403);
        }
        var contentId = PositiveInt.parse(request.query("content", ""));
        var limit = PositiveInt.parse(request.query("limit", ""),
            ViewCounts.MAX_LIMIT) ?? ViewCounts.PAGE_SIZE;
        var cursor = contentId == null ? Pagination.cursor(request) : null;
        var page = contentId == null ? ViewCounts.page(cursor,
            limit) : ViewCounts.single(contentId);
        var described = ViewCounts.describe(page.items);
        var items = [
            for (item in described)
                {
                    contentId: item.contentId,
                    title: item.title,
                    type: item.type,
                    url: item.url,
                    views: item.views
                }
        ];
        var hasNext = cursor == null ? page.hasMore : cursor.before || page.hasMore;
        var last = page.items.length == 0 ? null : page.items[page.items.length - 1];
        var next = !hasNext || last == null ? null : Pagination.token({
            id: last.id,
            value: Std.string(last.views),
            before: false
        });
        var totalViews = Std.int(ViewCounts.total());
        var result = {
            items: items,
            next: next,
            contentItems: ViewCounts.count(),
            views: totalViews
        };
        return ResponseBuilder.asJson(result);
    }
}
