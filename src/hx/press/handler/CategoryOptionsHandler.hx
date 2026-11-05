package hx.press.handler;

import hx.well.handler.AbstractHandler;
import hx.press.CategoryData;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

class CategoryOptionsHandler extends AbstractHandler {
    public function execute(request:Request):AbstractResponse {
        var query = request.query("q", "").substr(0, 80);
        return ResponseBuilder.asJson({categories: CategoryData.options(query)});
    }
}
