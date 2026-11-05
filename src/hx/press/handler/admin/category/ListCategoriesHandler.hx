package hx.press.handler.admin.category;

import hx.press.AdminController;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;

class ListCategoriesHandler extends AbstractHandler {
    public function execute(request:Request):AbstractResponse {
        return AdminController.categoryList(request);
    }
}
