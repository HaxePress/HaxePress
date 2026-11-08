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
    The views by country as JSON, most views first, for scripts and the
    plugin's MCP tool. `content` and `country` filter the rows, `cursor`
    continues a list and `limit` sets its length, at most 100.
**/
class CountryViewsData extends AbstractHandler implements ValidationResponder {
    var host:PluginHost;

    public function new(host:PluginHost) {
        super();
        this.host = host;
    }

    public override function validate():Bool {
        return request().validate([
            "content" => [Custom("cms.positive_int")],
            "country" => [String, Regex("^(?:[A-Z]{2}|UNKNOWN)\\z")],
            "limit" => [Custom("cms.positive_int", [CountryViewData.MAX_LIMIT])],
            "cursor" => [String, Max(512)]
        ]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        var error = I18n.t("Use a content ID, a two-letter country or UNKNOWN, a cursor from a previous answer and a limit of at most 100.",
            null, ViewCountPlugin.NAMESPACE);
        return ResponseBuilder.asJson({error: error}, 422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!host.can(ViewCountPlugin.CAPABILITY)) {
            return ResponseBuilder.asJson({error: "Access restricted."}, 403);
        }
        var selected = CountryViewsPage.filter(request);
        var limit = PositiveInt.parse(request.query("limit", ""),
            CountryViewData.MAX_LIMIT) ?? CountryViewData.PAGE_SIZE;
        var cursor = Pagination.cursor(request);
        var page = CountryViewData.page(selected, cursor, limit);
        var entries = CountryViewData.describe(page.items);
        var items = [
            for (entry in entries)
                {
                    contentId: entry.contentId,
                    title: entry.title,
                    type: entry.type,
                    url: entry.url,
                    country: entry.country,
                    views: entry.views
                }
        ];
        var result = {
            items: items,
            next: CountryViewData.next(page, cursor),
            total: CountryViewData.count(selected),
            countingCountries: ViewCountPlugin.countingCountries,
            countrySourceActive: CountryViewData.countrySourceActive()
        };
        return ResponseBuilder.asJson(result);
    }
}
