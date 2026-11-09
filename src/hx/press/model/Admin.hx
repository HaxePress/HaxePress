package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;
import hx.well.auth.IAuthenticatable;
import hx.press.database.DatabaseDate;

@:connection("default")
@:table("admins")
class Admin extends BaseModel<Admin> implements IAuthenticatable {
    public static var query:BaseModelQuery<Admin>;

    @:primary @:visible @:field public var id:Int;
    @:visible @:field public var email:String;
    @:field public var password:String;
    @:visible @:field public var name:String;
    @:visible @:field public var role:String = "owner";
    @:visible @:field public var active:Int = 1;

    /** The member's administration language; empty until they choose one. **/
    @:visible @:field public var ui_language:String = "";

    @:visible @:field public var created_at:DatabaseDate;

    public function getId():Dynamic
        return id;

    public function getPassword():String
        return password;
}
