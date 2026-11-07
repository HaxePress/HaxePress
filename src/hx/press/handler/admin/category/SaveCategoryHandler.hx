package hx.press.handler.admin.category;

import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.AdminController;
import hx.press.SiteController;
import hx.press.CategoryData;
import hx.press.ContentCache;
import hx.press.SiteSettingsStore;
import haxe.Exception;
import hx.press.validation.PositiveInt;
import hx.well.facades.DBStatic;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.Category;
import hx.press.model.ContentItem;
import hx.well.validator.ValidatorRule;
import hx.well.http.RequestStatic.request;
import hx.press.validation.ValidationResponder;
#if jvm
import org.sqlite.SQLiteException;
import org.sqlite.SQLiteErrorCode;
#end

class SaveCategoryHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        var current = request();
        if (!CmsAccess.can("taxonomy")) {
            return true;
        }
        var rawId = AdminController.input(current, "id", 30);
        var id = PositiveInt.parse(rawId);
        if (rawId != "" && (id == null || !Category.query.where("id", id).exists())) {
            return true;
        }
        return current.validate(["name" => [Required, String, Min(1), Max(200)]]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        var form = {
            id: AdminController.input(request, "id", 30),
            name: CategoryData.normalize(AdminController.input(request, "name", 200))
        };
        return AdminController.categoryList(request,
            "Use between 1 and 80 characters for the category name.", 422, form);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("taxonomy")) {
            return CmsController.forbidden(request);
        }
        var rawId = AdminController.input(request, "id", 30);
        var id = PositiveInt.parse(rawId);
        if (rawId != "" && id == null) {
            return SiteController.notFound(request);
        }
        var category = id == null ? null : Category.query.select(["id", "name"])
            .where("id", id)
            .limit(1)
            .first();
        if (rawId != "" && category == null) {
            return SiteController.notFound(request);
        }
        var name = CategoryData.normalize(AdminController.input(request, "name", 200));
        var form = {id: rawId, name: name};

        if (name.length < 1 || name.length > 80) {
            return AdminController.categoryList(request,
                "Use between 1 and 80 characters for the category name.", 422, form);
        }
        var key = CategoryData.key(name);
        var nameExists = Category.query.where("name_key", key).where("id", "!=", id ?? 0).exists();
        if (nameExists) {
            return AdminController.categoryList(request,
                "A category with this name already exists.", 422, form);
        }
        var renamed = category != null && category.name != name;
        try {
            if (category == null) {
                Category.query.insert([
                    "name" => name,
                    "name_key" => key,
                    "created_at" => SiteSettingsStore.timestamp(),
                    "updated_at" => SiteSettingsStore.timestamp()
                ]);
            } else if (category.name != name) {
                // Renaming the category and its existing items must succeed together.
                DBStatic.transaction(() -> {
                    ContentItem.query.where("category", category.name).update(["category" => name]);
                    category.update(["name" => name, "name_key" => key, "updated_at" => SiteSettingsStore.timestamp()]);
                });
            }
        } catch (error:Exception) {
            #if jvm
            var native:Dynamic = error.native;
            if (!Std.isOfType(native, SQLiteException)) {
                throw error;
            }
            var constraint:SQLiteException = cast native;
            if (constraint.getResultCode() != SQLiteErrorCode.SQLITE_CONSTRAINT_UNIQUE) {
                throw error;
            }
            #else
            // PHP's SQLite3 reports the constraint only in its message.
            if (error.message.indexOf("UNIQUE constraint failed") < 0) {
                throw error;
            }
            #end
            return AdminController.categoryList(request,
                "A category with this name already exists.", 422, form);
        }
        if (category == null || renamed) {
            ContentCache.categoriesChanged();
        }
        if (renamed) {
            ContentCache.contentChanged();
        }
        var notice = category == null ? "created" : "renamed";
        return ResponseBuilder.asRedirect('/admin/categories?notice=${notice}', 303);
    }
}
