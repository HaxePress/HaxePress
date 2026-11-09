package hx.press.handler.admin.category;

import hx.press.i18n.SiteTexts;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.AdminController;
import hx.press.SiteController;
import hx.press.ContentCache;
import hx.press.validation.PositiveInt;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.Category;
import hx.press.model.ContentItem;

class DeleteCategoryHandler extends AbstractHandler {
    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("taxonomy")) {
            return CmsController.forbidden(request);
        }
        var category = Category.query.select(["id", "name"])
            .where("id", PositiveInt.route(request, "id"))
            .limit(1)
            .first();
        if (category == null)
            return SiteController.notFound(request);
        if (ContentItem.query.where("category", category.name).exists())
            return AdminController.categoryList(request,
                "Move this category's content to another category before deleting it.", 422);
        category.delete();
        SiteTexts.forget(['category.${category.id}.name']);
        ContentCache.categoriesChanged();
        return ResponseBuilder.asRedirect("/admin/categories?notice=deleted", 303);
    }
}
