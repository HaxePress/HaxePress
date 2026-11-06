package hx.press.view;

import haxe.Json;
import sys.FileSystem;
import sys.io.File;
import wellout.check.ComponentLibrary;

/**
    Checks every application template against the view contract and
    prints the diagnostics with their source lines. Run it with
    `haxe tools/check_views.hxml`; it exits with 1 when a template has an
    error.
**/
class CheckViews {
    static function main() {
        var contract = ViewContract.build();
        var library = new ComponentLibrary(contract);
        for (name in ViewSources.names()) {
            library.add(name, ViewSources.source(name));
        }
        var errors = 0;
        var warnings = 0;
        for (name in ViewSources.names()) {
            var result = library.check(name);
            var source = ViewSources.source(name);
            for (diagnostic in result.diagnostics) {
                if (diagnostic.isError()) {
                    errors++;
                } else {
                    warnings++;
                }
                Sys.println(diagnostic.format(source, '${name}.well.html'));
            }
        }
        var themes = Sys.getEnv("CHECK_THEMES");
        var folders = themes == null || themes == "" ? [] : themes.split(":");
        var themeTemplates = 0;
        for (folder in folders) {
            var theme = new ComponentLibrary(contract, library, false);
            var sources:Map<String, String> = [];
            for (file in FileSystem.readDirectory(folder)) {
                if (StringTools.endsWith(file, ".well.html")) {
                    var name = file.substr(0, file.length - ".well.html".length);
                    sources.set(name, File.getContent('${folder}/${file}'));
                    themeTemplates++;
                    theme.add(name, sources.get(name));
                }
            }
            for (name => source in sources) {
                for (diagnostic in theme.check(name).diagnostics) {
                    if (diagnostic.isError()) {
                        errors++;
                    } else {
                        warnings++;
                    }
                    Sys.println(diagnostic.format(source, '${folder}/${name}.well.html'));
                }
            }
        }
        var designPath = Sys.getEnv("CHECK_DESIGN");
        if (designPath != null && designPath != "") {
            var document:Dynamic = Json.parse(File.getContent(designPath));
            var design = new ComponentLibrary(contract, library, false);
            var generated = DesignTemplates.generate(document);
            for (name => source in generated) {
                design.add(name, source);
                themeTemplates++;
            }
            for (name => source in generated) {
                for (diagnostic in design.check(name).diagnostics) {
                    if (diagnostic.isError()) {
                        errors++;
                        Sys.println(diagnostic.format(source, 'design:${name}'));
                    }
                }
            }
            if (Sys.getEnv("PRINT_DESIGN") != null) {
                Sys.println(generated.get(Sys.getEnv("PRINT_DESIGN")));
            }
        }
        Sys.println('${ViewSources.names().length} application and ${themeTemplates} theme templates, ${errors} errors, ${warnings} warnings');
        Sys.exit(errors == 0 ? 0 : 1);
    }
}
