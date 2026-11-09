package hx.press.view;

import wellout.ByteWriter;

/** The interface icons, written as inline SVG with the same paths as the former Icon component. */
class Icons {
    static final paths:Map<String, String> = [
        "align-left" => "M3 5h18M3 10h12M3 15h18M3 20h12",
        "align-center" => "M3 5h18M6 10h12M3 15h18M6 20h12",
        "align-right" => "M3 5h18M9 10h12M3 15h18M9 20h12",
        "columns" => "M3 3h18v18H3zM12 3v18",
        "globe" =>
        "M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18zM3 12h18M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9M12 3c-2.5 2.6-3.8 5.6-3.8 9s1.3 6.4 3.8 9",
        "move" => "M12 3v18M3 12h18m-13-4-5 4 5 4m8-8 5 4-5 4M8 8l4-5 4 5m-8 8 4 5 4-5",
        "database" => "M3 6c0-4 18-4 18 0s-18 4-18 0Zm0 0v12c0 4 18 4 18 0V6M3 12c0 4 18 4 18 0",
        "code" => "m8 5-6 7 6 7M16 5l6 7-6 7M14 3l-4 18",
        "link" =>
        "m10 13 4-4M8 16l-2 2a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0M16 8l2-2a4 4 0 0 1 6 6l-5 5a4 4 0 0 1-6 0",
        "refresh" => "M20 7V2l-3 3a9 9 0 1 0 3 11M20 7h-5",
        "undo" => "M3 10h10a7 7 0 0 1 0 14M3 10l6-6M3 10l6 6",
        "redo" => "M21 10H11a7 7 0 0 0 0 14M21 10l-6-6M21 10l-6 6",
        "grip" => "M9 5h.01M15 5h.01M9 12h.01M15 12h.01M9 19h.01M15 19h.01",
        "copy" => "M8 8h13v13H8zM16 8V3H3v13h5",
        "cursor" => "m4 3 16 9-8 2-3 8-5-19Z",
        "chevron-right" => "m9 5 7 7-7 7",
        "layers" => "m12 3 10 5-10 5L2 8l10-5ZM2 12l10 5 10-5M2 16l10 5 10-5",
        "palette" =>
        "M12 3a9 9 0 1 0 0 18h1a2 2 0 0 0 1-3.7 1.5 1.5 0 0 1 1-2.8h2a4 4 0 0 0 4-4C21 6.5 17 3 12 3ZM7 9h.01M10 6h.01M15 6h.01M18 9h.01",
        "puzzle" =>
        "M9 3H4v6h2a2 2 0 1 1 0 4H4v7h7v-2a2 2 0 1 1 4 0v2h6v-7h-2a2 2 0 1 1 0-4h2V3h-6v2a2 2 0 1 1-4 0V3H9",
        "eye-off" =>
        "m3 3 18 18M10.6 10.6a2 2 0 0 0 2.8 2.8M9.9 5.2A11 11 0 0 1 12 5c7 0 10 7 10 7a18 18 0 0 1-3.4 4.3M6.5 6.5A18 18 0 0 0 2 12s3 7 10 7a11 11 0 0 0 5.5-1.5",
        "desktop" => "M3 3h18v13H3zM12 16v5M7 21h10",
        "tablet" => "M5 2h14v20H5zM11 19h2",
        "mobile" => "M7 2h10v20H7zM11 19h2",
        "arrow-up-right" => "M7 17 17 7M7 7h10v10",
        "arrow-right" => "M5 12h14m-6-6 6 6-6 6",
        "arrow-left" => "M19 12H5m6-6-6 6 6 6",
        "arrow-down" => "M12 5v14m-6-6 6 6 6-6",
        "arrow-up" => "M12 19V5m-6 6 6-6 6 6",
        "image" => "M3 3h18v18H3zM3 16l5-5 5 5 3-3 5 5M9 7h.01",
        "upload" => "M12 16V3m-5 5 5-5 5 5M4 16v5h16v-5",
        "search" => "m21 21-4.5-4.5M19 11a8 8 0 1 1-16 0 8 8 0 0 1 16 0",
        "menu" => "M4 6h16M4 12h16M4 18h16",
        "x" => "m6 6 12 12M6 18 18 6",
        "clock" => "M12 8v4l3 2M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0",
        "mail" =>
        "M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Zm-2 3 10 6L22 7",
        "rss" => "M4 11a9 9 0 0 1 9 9M4 4a16 16 0 0 1 16 16M4 20h.01",
        "sparkles" =>
        "m12 3 2.4 6.6L21 12l-6.6 2.4L12 21l-2.4-6.6L3 12l6.6-2.4L12 3ZM21 2v4m-2-2h4",
        "share" =>
        "M12 16V3m-5 5 5-5 5 5M5 13H4a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1v-6a1 1 0 0 0-1-1h-1",
        "layout" => "M3 3h18v18H3zM3 9h18M9 9v12",
        "file" =>
        "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6Zm0 0v6h6M8 13h8M8 17h6",
        "users" =>
        "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M16 3a4 4 0 0 1 0 8M22 21v-2a4 4 0 0 0-3-3.87M13 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0",
        "settings" =>
        "m9.5 3-.6 2-2 .9-1.9-.5L3 9l1.4 1.5v2.9L3 15l2 3.5 1.9-.5 2 .9.6 2h5l.6-2 2-.9 1.9.5 2-3.5-1.4-1.6v-2.8L21 9l-2-3.6-1.9.5-2-.9-.6-2h-5ZM15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0",
        "feather" => "m20.24 12.24-7.7 7.7H4v-8.5l7.76-7.7a6 6 0 0 1 8.48 8.5ZM16 8 2 22M9 15h6",
        "plus" => "M12 5v14M5 12h14",
        "hash" => "M5 9h14M4 15h14M11 3 7 21M17 3l-4 18",
        "check" => "m5 12 4 4L19 6",
        "edit" => "m16 3 5 5M3 21l6-1L21 8a3.5 3.5 0 0 0-5-5L3 16v5Z",
        "trash" => "M3 6h18M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M5 6l1 14h12l1-14M10 10v7M14 10v7",
        "external" =>
        "M15 3h6v6m0-6L10 14M9 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-4",
        "logout" => "M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4m7 14 5-5-5-5M21 12H9",
        "grid" => "M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z",
        "eye" =>
        "M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7ZM15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0",
        "lock" => "M5 10h14v11H5zM8 10V6a4 4 0 0 1 8 0v4M12 15v2",
        "alert" => "M12 3 2 21h20L12 3ZM12 9v5M12 17h.01",
        "download" => "M12 3v12m-5-5 5 5 5-5M5 17v4h14v-4",
        "quote" =>
        "M3 5h7v8H6c0 3 2 5 2 5l-2 2s-4-3-4-8V5h1Zm12 0h7v8h-4c0 3 2 5 2 5l-2 2s-4-3-4-8V5h1",
        "list" => "M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01",
        "sun" =>
        "M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5 19 19M5 19l1.5-1.5M17.5 6.5 19 5M17 12a5 5 0 1 1-10 0 5 5 0 0 1 10 0",
        "compass" => "m16 8-3 5-5 3 3-5 5-3ZM22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0",
        "heart" =>
        "M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"
    ];

    /** Complete `<svg>` markup per icon, built once so writing an icon copies bytes only. **/
    static final markup:Map<String, String> = [
        for (name => path in paths)
            name =>
            '<svg viewBox="0 0 24 24" class="icon" aria-hidden="true"><path d="${path}"></path></svg>'
    ];

    public static function svg(name:String):String {
        var found = markup.get(name);
        return found == null ? markup.get("file") : found;
    }

    public static function write(name:String, writer:ByteWriter):Void {
        writer.trusted(svg(name));
    }

    public static function has(name:String):Bool {
        return paths.exists(name);
    }
}
