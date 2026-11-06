package hx.press;

import hx.press.data.QueryPage;
import haxe.Json;
import haxe.crypto.Base64;
import haxe.io.Bytes;
import haxe.extern.EitherType;
import hx.well.http.Request;

typedef CursorKey = EitherType<Int, String>;

typedef PageCursor = {
    var value:Null<String>;
    var id:CursorKey;
    var before:Bool;
}

typedef PageLinks = {
    var previous:Null<String>;
    var next:Null<String>;
    var total:Int;
}

class Pagination {
    public static function cursor(request:Request, stringKeys:Bool = false):Null<PageCursor> {
        var token = request.query("cursor", "");
        if (token == "" || token.length > 512)
            return null;
        try {
            var parts:Array<Dynamic> = Json.parse(Base64.urlDecode(token).toString());
            if (parts.length != 3 || !Std.isOfType(parts[2], Bool))
                return null;
            var validKey = stringKeys ? Std.isOfType(parts[1], String)
                && ~/^[A-Za-z0-9_-]{1,128}$/.match(parts[1]) : Std.isOfType(parts[1], Int)
                && parts[1] > 0;
            if (!validKey) {
                return null;
            }
            if (parts[0] != null
                && (!Std.isOfType(parts[0], String) || Std.string(parts[0]).length > 40))
                return null;
            return {value: parts[0], id: parts[1], before: parts[2]};
        } catch (error:Dynamic) {
            return null;
        }
    }

    public static function token(cursor:Null<PageCursor>):String {
        if (cursor == null)
            return "";
        return
            Base64.urlEncode(Bytes.ofString(Json.stringify([cursor.value, cursor.id, cursor.before])));
    }

    public static function slice<T>(rows:Array<T>, limit:Int,
            cursor:Null<PageCursor>):QueryPage<T> {
        var hasMore = rows.length > limit;
        var items = rows.slice(0, limit);
        if (cursor != null && cursor.before)
            items.reverse();
        return {items: items, hasMore: hasMore};
    }

    public static function links<T>(path:String, parameters:Map<String, String>,
            page:QueryPage<T>, cursor:Null<PageCursor>, total:Int, getId:T->CursorKey,
            getValue:T->Null<String>):PageLinks {
        var previous:Null<String> = null;
        var next:Null<String> = null;
        if (page.items.length > 0) {
            var hasPrevious = cursor != null && (!cursor.before || page.hasMore);
            var hasNext = cursor == null ? page.hasMore : cursor.before || page.hasMore;
            if (hasPrevious) {
                var first = page.items[0];
                previous = url(path, parameters,
                    {id: getId(first), value: getValue(first), before: true});
            }
            if (hasNext) {
                var last = page.items[page.items.length - 1];
                next = url(path, parameters,
                    {id: getId(last), value: getValue(last), before: false});
            }
        }
        return {previous: previous, next: next, total: total};
    }

    static function url(path:String, parameters:Map<String, String>, cursor:PageCursor):String {
        var values = parameters.copy();
        values.set("cursor", token(cursor));
        var pairs = [];
        for (key => value in values) {
            if (value != "")
                pairs.push('${StringTools.urlEncode(key)}=${StringTools.urlEncode(value)}');
        }
        return '${path}?${pairs.join("&")}';
    }
}
