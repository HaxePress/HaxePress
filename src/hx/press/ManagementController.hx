package hx.press;

import hx.press.content.ContentLocks;
import hx.press.AdminController;
import hx.press.SiteController;
import hx.press.ContentCache;
import hx.press.Pagination;
import hx.press.validation.PositiveInt;
import hx.well.facades.DBStatic;
import hx.press.view.View;
import hx.press.AdminForms;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.Admin;
import hx.press.model.ActivityLog;
import hx.press.model.MenuLink;
import hx.press.access.Roles;
import hx.press.navigation.NavigationRegions;
import hx.press.navigation.NavigationRegions.NavigationRegionRecord;

typedef TeamMemberRecord = {
    var id:Int;
    var name:String;
    var email:String;
    var role:String;
    var active:Int;
}

typedef ActivityEntryRecord = {
    var id:Int;
    var actor:String;
    var action:String;
    var entity:String;
    var entity_id:Int;
    var label:String;
    var created_at:String;
    var source:String;
}

typedef LinkFormRecord = {
    var id:String;
    var label:String;
    var url:String;
    var position:String;
    var content_id:String;
    var collection_key:String;
    var new_tab:Bool;
    var mode:String;
}

typedef RegionFormRecord = {
    var key:String;
    var name:String;
    var max_links:String;
    var enabled:Bool;
}

typedef MemberFormRecord = {
    var id:String;
    var name:String;
    var email:String;
    var role:String;
    var active:Bool;
    var own:Bool;
}

class ManagementController {
    static final activityKinds = [
        "entry",
        "page",
        "tag",
        "category",
        "media",
        "plugin",
        "theme",
        "navigation",
        "member"
    ];

    public static function navigation(request:Request, error:String = "",
            status:Int = 200):AbstractResponse {
        if (!CmsAccess.can("navigation")) {
            return CmsController.forbidden(request);
        }
        var submittedLocation = AdminController.input(request, "location", 41);
        var returnLocation = NavigationRegions.validKey(submittedLocation) ? submittedLocation : "";
        var returnUrl = AdminForms.returnUrl(request, "/admin/navigation",
            ["location" => returnLocation]);
        var redirect = AdminController.validationRedirect(request, "navigation", error, returnUrl);
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
        var regionQuery = StringTools.trim(request.query("region_query", "")).substr(0, 100);
        var linkForm = linkForm(request, links);
        var linkContentId = Std.parseInt(linkForm.content_id) ?? 0;
        var linkContent = linkForm.mode == "content" ? AdminForms.publishedContent(linkContentId) : null;
        var linkCollection = linkForm.mode == "collection" ? AdminForms.publicCollection(linkForm.collection_key,
            true) : null;
        var props:Map<String, Dynamic> = [
            "links" => links,
            "location" => location,
            "regions" => NavigationRegions.options(regionQuery, location),
            "region" => region,
            "limit" => region.max_links,
            "notice" => request.query("notice",
                "") == "saved" ? "Navigation has been updated." : "",
            "regionQuery" => regionQuery,
            "linkForm" => linkForm,
            "linkContent" => linkContent,
            "linkCollection" => linkCollection,
            "regionForm" => regionForm(request, region)
        ];
        if (error != "") {
            props.set("errors", ["navigation" => error]);
        }
        return View.render("Admin/Navigation", props).status(status);
    }

    /** The link form: a failed submission, the listed link in `?edit=`, or a new link. **/
    static function linkForm(request:Request, links:Array<Dynamic>):LinkFormRecord {
        if (AdminForms.resubmitted(request, "label")) {
            var target = AdminForms.old(request, "target", "url");
            return {
                id: AdminForms.old(request, "id", ""),
                label: AdminForms.old(request, "label", ""),
                url: AdminForms.old(request, "url", ""),
                position: AdminForms.old(request, "position", Std.string(links.length)),
                content_id: AdminForms.old(request, "content_id", "0"),
                collection_key: AdminForms.old(request, "collection_key", ""),
                new_tab: AdminForms.old(request, "new_tab", "0") == "1",
                mode: ["url", "content", "collection"].contains(target) ? target : "url"
            };
        }
        var editId = AdminForms.editId(request);
        var edited:Dynamic = Lambda.find(links, link -> link.id == editId);
        if (edited == null) {
            return {
                id: "",
                label: "",
                url: "",
                position: Std.string(links.length),
                content_id: "0",
                collection_key: "",
                new_tab: false,
                mode: "url"
            };
        }
        var contentId:Int = edited.content_id;
        var collectionKey:String = edited.collection_key ?? "";
        var mode = contentId > 0 ? "content" : collectionKey != "" ? "collection" : "url";
        return {
            id: Std.string(edited.id),
            label: edited.label,
            url: edited.url,
            position: Std.string(edited.position),
            content_id: Std.string(contentId),
            collection_key: collectionKey,
            new_tab: edited.new_tab == 1,
            mode: mode
        };
    }

    /** The region form: a failed submission, the current region with `?region=edit`, or a new region. **/
    static function regionForm(request:Request, region:NavigationRegionRecord):RegionFormRecord {
        if (AdminForms.resubmitted(request, "max_links")) {
            return {
                key: AdminForms.old(request, "key", ""),
                name: AdminForms.old(request, "name", ""),
                max_links: AdminForms.old(request, "max_links", "12"),
                enabled: AdminForms.old(request, "enabled", "0") == "1"
            };
        }
        if (request.query("region", "") == "edit") {
            return {
                key: region.key,
                name: region.name,
                max_links: Std.string(region.max_links),
                enabled: region.enabled == 1
            };
        }
        return {
            key: "",
            name: "",
            max_links: "12",
            enabled: true
        };
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
                .where("id", PositiveInt.route(request, "id"))
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
        var returnUrl = AdminForms.returnUrl(request, "/admin/team");
        var redirect = AdminController.validationRedirect(request, "team", error, returnUrl);
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
        var actor = CmsAccess.current();
        var memberForm = memberForm(request, page.items, actor.id);
        var selectedRoles = [for (member in page.items) member.role];
        if (memberForm != null && !selectedRoles.contains(memberForm.role)) {
            selectedRoles.push(memberForm.role);
        }
        var roleChoices = Roles.options(CmsAccess.capabilities(actor.role), selectedRoles);
        if (memberForm == null) {
            var writerEnabled = Lambda.exists(roleChoices,
                role -> role.key == "writer" && role.enabled == 1);
            memberForm = {
                id: "",
                name: "",
                email: "",
                role: writerEnabled ? "writer" : "",
                active: true,
                own: false
            };
        }
        var members = [
            for (member in page.items)
                {
                    id: member.id,
                    name: member.name,
                    email: member.email,
                    role: member.role,
                    active: member.active,
                    roleLabel: AdminForms.label(member.role)
                }
        ];
        var props:Map<String, Dynamic> = [
            "members" => members,
            "roleChoices" => roleChoices,
            "query" => search,
            "total" => total,
            "pagination" => links,
            "notice" => request.query("notice",
                "") == "saved" ? "Team member details have been saved." : "",
            "memberForm" => memberForm
        ];
        if (error != "") {
            props.set("errors", ["team" => error]);
        }
        return View.render("Admin/Team", props).status(status);
    }

    /** The member form of a failed submission or of the member in `?edit=`; null for a new member. **/
    static function memberForm(request:Request, listed:Array<TeamMemberRecord>,
            actorId:Int):Null<MemberFormRecord> {
        if (AdminForms.resubmitted(request, "email")) {
            var id = AdminForms.old(request, "id", "");
            return {
                id: id,
                name: AdminForms.old(request, "name", ""),
                email: AdminForms.old(request, "email", ""),
                role: AdminForms.old(request, "role", ""),
                active: AdminForms.old(request, "active", "0") == "1",
                own: id == Std.string(actorId)
            };
        }
        var editId = AdminForms.editId(request);
        var edited = Lambda.find(listed, member -> member.id == editId);
        if (edited == null && editId > 0) {
            var row = Admin.query.select(["id", "name", "email", "role", "active"])
                .where("id", editId)
                .limit(1)
                .first();
            edited = row == null ? null : cast row.toObject();
        }
        if (edited == null) {
            return null;
        }
        return {
            id: Std.string(edited.id),
            name: edited.name,
            email: edited.email,
            role: edited.role,
            active: edited.active == 1,
            own: edited.id == actorId
        };
    }

    public static function activity(request:Request):AbstractResponse {
        if (!CmsAccess.can("activity")) {
            return CmsController.forbidden(request);
        }
        var entity = request.query("entity", "").substr(0, 30);
        var cursor = Pagination.cursor(request);
        var query = ActivityLog.query.select(["id", "actor", "action", "entity", "entity_id", "label", "created_at", "source"]);
        var counter = ActivityLog.query.select(["id"]);
        if (entity != "") {
            query.where("entity", entity);
            counter.where("entity", entity);
        }
        if (cursor != null) {
            query.where("id", cursor.before ? ">" : "<", cursor.id);
        }
        var direction = cursor != null && cursor.before ? "ASC" : "DESC";
        var rows:Array<ActivityEntryRecord> = query.orderBy("id", direction)
            .limit(31)
            .get()
            .map(model -> cast model.toObject());
        var page = Pagination.slice(rows, 30, cursor);
        var total = counter.count();
        var links = Pagination.links("/admin/activity", ["entity" => entity], page, cursor, total,
            entry -> entry.id, entry -> null);
        var entries = [
            for (entry in page.items)
                {
                    id: entry.id,
                    actor: entry.actor,
                    action: entry.action,
                    entity: entry.entity,
                    entity_id: entry.entity_id,
                    label: entry.label ?? "",
                    created_at: entry.created_at,
                    actionKey: 'activity.${entry.action}',
                    datetime: StringTools.replace(entry.created_at, " ", "T"),
                    mcp: entry.source == Activity.MCP
                }
        ];
        var entityChoices = [
            for (kind in activityKinds)
                {value: kind, label: AdminForms.label(kind)}
        ];
        var props = {
            entries: entries,
            entity: entity,
            total: total,
            pagination: links,
            entityChoices: entityChoices
        };
        return View.render("Admin/Activity", props);
    }

    public static function account(request:Request, error:String = "", status:Int = 200,
            scope:String = "account"):AbstractResponse {
        var redirect = AdminController.validationRedirect(request, scope, error, "/admin/account");
        if (redirect != null) {
            return redirect;
        }
        var admin = CmsAccess.current();
        var props:Map<String, Dynamic> = [
            "member" => {
                name: admin.name,
                email: admin.email,
                role: admin.role,
                roleLabel: AdminForms.label(admin.role)
            },
            "notice" => request.query("notice",
                "") == "saved" ? "Your account details have been saved." : request.query("notice",
                "") == "password" ? "Your password has been updated." : ""
        ];
        if (error != "") {
            props.set("errors", [scope => error]);
        }
        return View.render("Admin/Account", props).status(status);
    }
}
