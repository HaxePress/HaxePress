package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

/** An MCP link of an administrator: only a hash of its token is kept. */
@:connection("default")
@:table("admin_mcp_links")
class AdminMcpLink extends BaseModel<AdminMcpLink> {
    public static var query:BaseModelQuery<AdminMcpLink>;

    @:primary @:field public var id:String = "";
    @:field public var admin_id:Int = 0;
    @:field public var auth_version:String = "";
    @:field public var profile:String = "";
    @:field public var origin:String = "";
    @:field public var token_hash:String = "";
    @:field public var expires_epoch:Float = 0;

    /** 0 until a client first uses the link. */
    @:field public var first_seen_epoch:Float = 0;

    @:field public var last_seen_epoch:Float = 0;
    @:field public var created_epoch:Float = 0;
}
