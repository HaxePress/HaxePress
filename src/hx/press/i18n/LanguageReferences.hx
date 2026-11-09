package hx.press.i18n;

import hx.press.model.ContentItem;
import hx.press.model.Language;
import hx.press.model.MenuLink;
import hx.press.model.Translation;

/**
    The records that name a language by its code. Renaming a language
    updates them; a language that content or navigation still uses cannot
    be deleted.
**/
class LanguageReferences {
    /** Why a language cannot be deleted, or null when nothing uses it. **/
    public static function usage(code:String):Null<String> {
        if (ContentItem.query.where("language", code).exists()) {
            return "Content is written in this language. Move or delete it first.";
        }
        if (MenuLink.query.where("language", code).exists()) {
            return "Navigation links are shown only in this language. Change them first.";
        }
        return null;
    }

    /** Points every record of `previous` at `code`. Runs inside the rename transaction. **/
    public static function rename(previous:String, code:String):Void {
        ContentItem.query.where("language", previous).update(["language" => code]);
        MenuLink.query.where("language", previous).update(["language" => code]);
        Translation.query.where("language", previous).update(["language" => code]);
    }

    /**
        Removes the site's translations into a deleted language. The
        translations packages ship stay listed, ready for when the language
        is added again.
    **/
    public static function forget(code:String):Void {
        Translation.query.where("language", code).where("shipped", "").delete();
        Translation.query.where("language", code).update(["value" => "", "outdated" => 0]);
    }
}
