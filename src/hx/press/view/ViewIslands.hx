package hx.press.view;

import wellout.check.HostContract;
import wellout.check.Types;

/**
    Client islands (SPEC §9.3): interactive widgets mounted into
    server-rendered pages. Each island is built from
    `resources/js/islands/<name>.tsx` and receives only its typed props.
**/
class ViewIslands {
    public static function register(contract:HostContract):Void {
        for (island in islands()) {
            contract.addIsland(island);
        }
    }

    /** The fields every React island receives to load its translations. **/
    public static function reactContext():Array<FieldInfo> {
        return [
            new FieldInfo("translations", TUrl),
            new FieldInfo("locale", TString),
            new FieldInfo("direction", TString)
        ];
    }

    static function react(name:String, fields:Array<FieldInfo>):IslandSignature {
        return new IslandSignature(name, TRecord(reactContext().concat(fields)));
    }

    static function islands():Array<IslandSignature> {
        return [
            // Enhances a server-rendered admin form: dependent fields, option search, slugs.
            new IslandSignature("admin-form", TRecord([new FieldInfo("translations", TUrl)])),
            react("site-logo",
                [
                    new FieldInfo("csrfToken", TString),
                    new FieldInfo("logo", TString),
                    new FieldInfo("siteName", TString),
                    new FieldInfo("mediaRules", TView("SettingsMediaRulesView"))
                ]),
            react("admin-ai",
                [new FieldInfo("adminId", TInt), new FieldInfo("csrfToken", TString)]),
            react("theme-builder",
                [
                    new FieldInfo("studio", TAny),
                    new FieldInfo("csrfToken", TString),
                    new FieldInfo("auth", TAny)
                ]),
            react("theme-create",
                [new FieldInfo("baseDocument", TAny), new FieldInfo("csrfToken", TString)]),
            react("design-canvas", [
                new FieldInfo("name", TString),
                new FieldInfo("url", TString),
                new FieldInfo("pageProps", TAny),
                new FieldInfo("shared", TAny)
            ]),
            react("content-editor", [
                new FieldInfo("csrfToken", TString),
                new FieldInfo("siteUrl", TString),
                new FieldInfo("error", TString),
                new FieldInfo("editor", TView("ContentEditorView"))
            ]),
            // Device sizes, the customizer panel and live customization of the preview frame.
            new IslandSignature("theme-preview", TRecord([new FieldInfo("saved", TMap(TString))]),
                [
                    "Loading preview…",
                    "Unsaved changes",
                    "All changes saved",
                    "Save or discard changes before activating."
                ]),
            // Keeps server-rendered package setting controls in step (color toggle and picker).
            new IslandSignature("package-settings", TRecord([])),
            new IslandSignature("share",
                TRecord([new FieldInfo("title", TString), new FieldInfo("toast", TBool)]),
                ["Link copied to clipboard.", "Copy this link: {url}"]),
            new IslandSignature("content-type-editor",
                TRecord([new FieldInfo("siteUrl", TString), new FieldInfo("creating", TBool)]),
                ["New field"]),
            react("media-upload",
                [
                    new FieldInfo("csrfToken", TString),
                    new FieldInfo("rules", TView("ContentAdminMediaRulesView")),
                    new FieldInfo("notice", TString),
                    new FieldInfo("error", TString)
                ]),
            react("media-references",
                [new FieldInfo("images", TList(TView("ContentAdminMediaReferenceView")))]),
            // Live capability search of the role editor; keeps the selection across searches.
            react("role-capabilities", [
                new FieldInfo("choices", TList(TView("RoleCapabilityView"))),
                new FieldInfo("selected", TList(TString)),
                new FieldInfo("grantable", TList(TString))
            ]),
            // Inspects a plugin or theme ZIP, then opens its server-rendered inspection.
            react("package-upload", [
                new FieldInfo("base", TString),
                new FieldInfo("label", TString),
                new FieldInfo("uploadLimit", TInt),
                new FieldInfo("disabled", TBool),
                new FieldInfo("csrfToken", TString)
            ]),
            // Captures a theme preview frame into the thumbnail of a theme card.
            new IslandSignature("theme-thumbnail", TRecord([new FieldInfo("source", TString)]),
                ["Preview unavailable"]),
            // Uploads a backup in chunks and rehearses its restore.
            react("backup-restore-check",
                [new FieldInfo("uploadLimit", TInt), new FieldInfo("csrfToken", TString)]),
            // Sends a datetime-local field of its form as epoch milliseconds in the browser's zone.
            new IslandSignature("local-datetime", TRecord([])),
            // Restores a backup from the installer; the installer has no catalogue, like before.
            new IslandSignature("install-restore", TRecord([
                new FieldInfo("restoreLimit", TInt),
                new FieldInfo("csrfToken", TString),
                new FieldInfo("useVerifiedDatabase", TBool)
            ]))
        ];
    }
}
