package example.reading;

import hx.press.plugins.PluginEntrypoint;
import hx.press.plugins.PluginHost;
import haxe.Json;
import hx.press.i18n.I18n;

class ReadingPlugin implements PluginEntrypoint {
    public function new() {}

    public function onCreate(host:PluginHost, context:String):Void {}

    public function onDestroy():Void {}

    public function dispatch(event:String, context:String):String {
        var input:Dynamic = Json.parse(context);
        var message:String = input.settings.message;

        if (event == "site.shared") {
            var result = {
                blocks: [
                    {
                        slot: "site.footer",
                        content: message
                    }
                ]
            };
            return Json.stringify(result);
        }
        if (event == "content.render" && input.settings.content_note == "true") {
            return Json.stringify({content: '${input.data.content}\n\n---\n\n${message}'});
        }
        if (event == "content.saving" && input.data.document.status != "draft") {
            var content:String = input.data.document.content;
            var minimum = Std.parseInt(input.settings.minimum_characters) ?? 0;
            if (StringTools.trim(content).length < minimum) {
                return Json.stringify({
                    error: I18n.t("Reading Companion requires at least {minimum} content characters before site.",
                        ["minimum" => minimum], "plugin-reading-companion")
                });
            }
        }
        if (event == "dashboard.widgets") {
            var heading = I18n.t("Reading Companion", null, "plugin-reading-companion");
            var summary = I18n.t("Your reading note is active on the public site.", null,
                "plugin-reading-companion");
            return Json.stringify({
                blocks: [
                    {
                        slot: "dashboard",
                        content: '### ${heading}\n\n${summary}'
                    }
                ]
            });
        }
        return "{}";
    }
}
