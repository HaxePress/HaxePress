package extensions.viewcount;

import extensions.viewcount.CountryViewData.CountryViewFilter;
import hx.press.Pagination;
import hx.press.i18n.I18n;
import hx.press.plugins.PluginHost;
import hx.press.validation.PositiveInt;
import hx.press.view.Pages;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

/**
    The administration page of the views by country, most views first. It
    lists one content item with `?content=<id>`, one country with
    `?country=TR`, or both, and says when the plugin does not count
    countries or the Cloudflare plugin that provides them is inactive.
**/
class CountryViewsPage extends AbstractHandler {
    var host:PluginHost;

    public function new(host:PluginHost) {
        super();
        this.host = host;
    }

    /** The filter in the page's address; values that are not valid are left out. **/
    public static function filter(request:Request):CountryViewFilter {
        var country = request.query("country", "");
        return {
            content: PositiveInt.parse(request.query("content", "")),
            country: CountryViewData.validCountry(country) ? country : null
        };
    }

    /** `base` with the filter of `content` and `country`, and an optional `limit`. **/
    static function address(base:String, content:Null<Int>, country:Null<String>,
            ?limit:Int):String {
        var parameters:Array<String> = [];
        if (content != null) {
            parameters.push('content=${content}');
        }
        if (country != null) {
            parameters.push('country=${country}');
        }
        if (limit != null) {
            parameters.push('limit=${limit}');
        }
        var query = parameters.length == 0 ? "" : '?${parameters.join("&")}';
        return '${base}${query}';
    }

    public function execute(request:Request):AbstractResponse {
        if (!host.can(ViewCountPlugin.CAPABILITY)) {
            return ResponseBuilder.asString("Access restricted.", 403);
        }
        var selected = filter(request);
        var cursor = Pagination.cursor(request);
        var page = CountryViewData.page(selected, cursor, CountryViewData.PAGE_SIZE);
        var total = CountryViewData.count(selected);
        var entries = CountryViewData.describe(page.items);
        var rows = [
            for (entry in entries)
                {
                    title: entry.title,
                    url: entry.url,
                    country: entry.country,
                    views: entry.views,
                    contentAddress: address(ViewCountPlugin.COUNTRY_PAGE, entry.contentId,
                        selected.country),
                    countryAddress: address(ViewCountPlugin.COUNTRY_PAGE, selected.content,
                        entry.country)
                }
        ];
        var parameters:Map<String, String> = [];
        if (selected.content != null) {
            parameters.set("content", Std.string(selected.content));
        }
        if (selected.country != null) {
            parameters.set("country", selected.country);
        }
        var links = Pagination.links(ViewCountPlugin.COUNTRY_PAGE, parameters, page, cursor,
            total, record -> record.id, record -> Std.string(record.views));
        var contentTitle = selected.content == null ? null : CountryViewData.title(selected.content);
        var label = I18n.t("All content and countries", null, ViewCountPlugin.NAMESPACE);
        if (contentTitle != null && selected.country != null) {
            label = I18n.t("{content} from {country}",
                ["content" => contentTitle, "country" => selected.country],
                ViewCountPlugin.NAMESPACE);
        } else if (contentTitle != null) {
            label = contentTitle;
        } else if (selected.country != null) {
            label = I18n.t("Content viewed from {country}", ["country" => selected.country],
                ViewCountPlugin.NAMESPACE);
        }
        var dataAddress = address('${ViewCountPlugin.COUNTRY_PAGE}/data', selected.content,
            selected.country, CountryViewData.MAX_LIMIT);
        var props = {
            rows: rows,
            heading: label,
            filtered: selected.content != null || selected.country != null,
            pagination: links,
            total: total,
            countingCountries: ViewCountPlugin.countingCountries,
            countrySourceActive: CountryViewData.countrySourceActive(),
            settingsAddress: ViewCountPlugin.SETTINGS_PAGE,
            dataAddress: dataAddress
        };
        return Pages.view("CountryViews", props);
    }
}
