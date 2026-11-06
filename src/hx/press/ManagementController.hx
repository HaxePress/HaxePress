package hx.press;

import hx.press.content.ContentLocks;
import hx.press.AdminController;
import hx.press.SiteController;
import hx.press.ContentCache;
import hx.press.Pagination;
import hx.well.facades.DBStatic;
import hx.well.facades.Inertia;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.Admin;
import hx.press.model.ActivityLog;
import hx.press.model.MenuLink;
import hx.press.access.Roles;
import hx.press.navigation.NavigationRegions;

typedef TeamMemberRecord = {
    var id:Int;
    var name:String;
    var email:String;
    var role:String;
    var active:Int;
}

class ManagementController {
    public static function navigation(request:Request, error:String = "",
            status:Int = 200):AbstractResponse {
        if (!CmsAccess.can("navigation")) {
            return CmsController.forbidden(request);
        }
        var redirect = AdminController.validationRedirect(request, "navigation", error,
            "/admin/navigation");
        if (redirect != null) {
            return redirect;
        }
        var location = request.query("location", "header").substr(0, 40);
        var region = NavigationRegions.find(location);
        if (region == null) {
            return SiteController.notFound(request);
        }
        var links:Array<Dynamic> = MenuLink.query.select(["id", "label", "url", "position", "new_tab", "content_id", "collection_key"])
            .where("location", location)
            .orderBy("position")
            .orderBy("id")
            .limit(region.max_links)
            .get()
            .map(model -> cast model.toObject());
        var props:Map<String, Dynamic> = [
            "links" => links,
            "location" => location,
            "regions" => NavigationRegions.options("", location),
            "region" => region,
            "limit" => region.max_links,
            "notice" => request.query("notice", "") == "saved" ? "Navigation has been updated." : ""
        ];
        if (error != "") {
            props.set("errors", ["navigation" => error]);
        }
        return Inertia.render("Admin/Navigation", props).status(status);
    }

    public static function regionOptions(request:Request):AbstractResponse {
        if (!CmsAccess.can("navigation")) {
            return ResponseBuilder.asJson({error: "Access restricted."}, 403);
        }
        return ResponseBuilder.asJson({
            regions: NavigationRegions.options(request.query("q", "").substr(0, 100),
                request.query("selected", "").substr(0, 40))
        });
    }

    public static function deleteNavigation(request:Request):AbstractResponse {
        if (!CmsAccess.can("navigation")) {
            return CmsController.forbidden(request);
        }
        return ContentLocks.run("navigation", () -> {
            var link = MenuLink.query.select(["id", "label", "location"])
                .where("id", Std.parseInt(request.route("id")))
                .limit(1)
                .first();
            if (link == null) {
                return SiteController.notFound(request);
            }
            DBStatic.transaction(() -> {
                link.delete();
                Activity.record("deleted", "navigation", link.id, link.label);
            });
            ContentCache.changed("navigation");
            return
                ResponseBuilder.asRedirect('/admin/navigation?location=${link.location}&notice=saved',
                    303);
        });
    }

    public static function team(request:Request, error:String = "",
            status:Int = 200):AbstractResponse {
        if (!CmsAccess.can("team")) {
            return CmsController.forbidden(request);
        }
        var redirect = AdminController.validationRedirect(request, "team", error, "/admin/team");
        if (redirect != null) {
            return redirect;
        }
        var search = StringTools.trim(request.query("q", "")).substr(0, 100);
        var cursor = Pagination.cursor(request);
        var query = Admin.query.select(["id", "name", "email", "role", "active"]);
        var counter = Admin.query.select(["id"]);
        if (search != "") {
            var escaped = StringTools.replace(StringTools.replace(StringTools.replace(search, "!",
                "!!"), "%", "!%"), "_", "!_");
            for (builder in [query, counter]) {
                builder.where(matches -> {
                    matches.whereLike("name", '%${escaped}%').orWhereLike("email", '%${escaped}%');
                });
            }
        }
        if (cursor != null) {
            query.where("id", cursor.before ? "<" : ">", cursor.id);
        }
        var direction = cursor != null && cursor.before ? "DESC" : "ASC";
        var rows:Array<TeamMemberRecord> = query.orderBy("id", direction)
            .limit(21)
            .get()
            .map(model -> cast model.toObject());
        var page = Pagination.slice(rows, 20, cursor);
        var total = counter.count();
        var links = Pagination.links("/admin/team", ["q" => search], page, cursor, total,
            member -> member.id, member -> null);
        var props:Map<String, Dynamic> = [
            "members" => page.items,
            "roleChoices" => Roles.options(CmsAccess.capabilities(CmsAccess.current().role),
                [for (member in page.items) member.role]),
            "query" => search,
            "total" => total,
            "pagination" => links,
            "notice" => request.query("notice",
                "") == "saved" ? "Team member details have been saved." : ""
        ];
        if (error != "") {
            props.set("errors", ["team" => error]);
        }
        return Inertia.render("Admin/Team", props).status(status);
    }

    public static function activity(request:Request):AbstractResponse {
        if (!CmsAccess.can("activity")) {
            return CmsController.forbidden(request);
        }
        var entity = request.query("entity", "").substr(0, 30);
        var cursor = Pagination.cursor(request);
        var query = ActivityLog.query.select(["id", "actor", "action", "entity", "entity_id", "label", "created_at"]);
        var counter = ActivityLog.query.select(["id"]);
        if (entity != "") {
            query.where("entity", entity);
            counter.where("entity", entity);
        }
        if (cursor != null) {
            query.where("id", cursor.before ? ">" : "<", cursor.id);
        }
        var direction = cursor != null && cursor.before ? "ASC" : "DESC";
        var rows:Array<Dynamic> = query.orderBy("id", direction)
            .limit(31)
            .get()
            .map(model -> cast model.toObject());
        var page = Pagination.slice(rows, 30, cursor);
        var total = counter.count();
        var links = Pagination.links("/admin/activity", ["entity" => entity], page, cursor, total,
            entry -> entry.id, entry -> null);
        var props = {
            entries: page.items,
            entity: entity,
            total: total,
            pagination: links
        };
        return Inertia.render("Admin/Activity", props);
    }

    public static function account(request:Request, error:String = "",
            status:Int = 200):AbstractResponse {
        var redirect = AdminController.validationRedirect(request, "account", error,
            "/admin/account");
        if (redirect != null) {
            return redirect;
        }
        var admin = CmsAccess.current();
        var props:Map<String, Dynamic> = [
            "member" => {name: admin.name, email: admin.email, role: admin.role},
            "notice" => request.query("notice",
                "") == "saved" ? "Your account details have been saved." : request.query("notice",
                "") == "password" ? "Your password has been updated." : ""
        ];
        if (error != "") {
            props.set("errors", ["account" => error]);
        }
        return Inertia.render("Admin/Account", props).status(status);
    }
}
