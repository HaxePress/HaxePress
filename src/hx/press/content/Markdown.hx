package hx.press.content;

import wellout.SafeHtml;
#if (target.threaded)
import sys.thread.Mutex;
#end

using StringTools;

private enum Block {
    Heading(level:Int, text:String);
    Paragraph(lines:Array<String>);
    Code(language:String, text:String);
    Quote(blocks:Array<Block>);
    ListBlock(ordered:Bool, start:Int, items:Array<ListItem>, loose:Bool);
    Rule;
    Table(header:Array<String>, alignments:Array<String>, rows:Array<Array<String>>);
}

private class ListItem {
    public final blocks:Array<Block>;
    public final task:Null<Bool>;

    public function new(blocks:Array<Block>, task:Null<Bool>) {
        this.blocks = blocks;
        this.task = task;
    }
}

private class LinkDefinition {
    public final url:String;
    public final title:Null<String>;

    public function new(url:String, title:Null<String>) {
        this.url = url;
        this.title = title;
    }
}

/**
    Renders content Markdown (CommonMark with GitHub tables, task lists,
    strikethrough and autolinks) to safe HTML on the server, with the rules
    of the former browser renderer: raw HTML is written as text, headings
    get `content-` ids, `#` headings become `<h2>`, only managed media
    images are shown, image-only paragraphs become figures, external links
    open in a new tab and tables scroll in a wrapper.
**/
class Markdown {
    static inline final CACHE_LIMIT = 128;
    static final cache:Map<String, String> = [];
    static final order:Array<String> = [];
    #if (target.threaded)
    static final lock = new Mutex();
    #end

    static final atxHeading = ~/^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$/;
    static final rule = ~/^ {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$/;
    static final fence = ~/^( {0,3})(`{3,}|~{3,})[ \t]*([^`]*)$/;
    static final bullet = ~/^( {0,3})([-*+])([ \t]+|$)(.*)$/;
    static final ordered = ~/^( {0,3})(\d{1,9})([.)])([ \t]+|$)(.*)$/;
    static final setextOne = ~/^ {0,3}=+[ \t]*$/;
    static final setextTwo = ~/^ {0,3}-+[ \t]*$/;
    static final definition = ~/^ {0,3}\[([^\]]+)\]:[ \t]*<?([^\s>]+)>?(?:[ \t]+(?:"([^"]*)"|'([^']*)'|\(([^)]*)\)))?[ \t]*$/;
    static final tableDelimiter = ~/^ *\|? *:?-+:? *(\| *:?-+:? *)*\|? *$/;
    static final task = ~/^\[([ xX])\][ \t]+(.*)$/s;
    static final mediaImage = ~/^\/media\/[A-Za-z0-9_-]{32}\.(jpg|png|webp|gif)$/;
    static final autolinkUrl = ~/^(?:https?:\/\/|www\.)[^\s<]*[^\s<?!.,:*_~)'"\]]/i;
    static final email = ~/^[A-Za-z0-9._+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+/;

    final definitions:Map<String, LinkDefinition> = [];
    final slugs:Map<String, Int> = [];
    final images:Null<Array<String>>;

    function new(?images:Array<String>) {
        this.images = images;
    }

    public static function render(source:Null<String>):SafeHtml {
        if (source == null || source == "") {
            return SafeHtml.trust("");
        }
        var cached = cachedHtml(source);
        if (cached != null) {
            return SafeHtml.trust(cached);
        }
        var markdown = new Markdown();
        var html = markdown.document(source);
        store(source, html);
        return SafeHtml.trust(html);
    }

    /** The destinations of every image in `source`, including the ones the renderer leaves out. **/
    public static function imageUrls(source:String):Array<String> {
        var urls:Array<String> = [];
        var markdown = new Markdown(urls);
        markdown.document(source);
        return urls;
    }

    static function cachedHtml(source:String):Null<String> {
        #if (target.threaded)
        lock.acquire();
        var found = cache.get(source);
        lock.release();
        return found;
        #else
        return cache.get(source);
        #end
    }

    static function store(source:String, html:String):Void {
        #if (target.threaded)
        lock.acquire();
        #end
        if (!cache.exists(source)) {
            order.push(source);
            if (order.length > CACHE_LIMIT) {
                cache.remove(order.shift());
            }
        }
        cache.set(source, html);
        #if (target.threaded)
        lock.release();
        #end
    }

    function document(source:String):String {
        var lines = source.replace("\r\n", "\n").replace("\r", "\n").split("\n");
        var content:Array<String> = [];
        for (line in lines) {
            if (definition.match(line)) {
                var key = normalizeLabel(definition.matched(1));
                if (!definitions.exists(key)) {
                    var title = definition.matched(3) ?? definition.matched(4) ?? definition.matched(5);
                    definitions.set(key, new LinkDefinition(definition.matched(2), title));
                }
                continue;
            }
            content.push(expandTabs(line));
        }
        var output = new StringBuf();
        blocksHtml(parseBlocks(content), output, false);
        return output.toString();
    }

    static function expandTabs(line:String):String {
        if (line.indexOf("\t") < 0) {
            return line;
        }
        var output = new StringBuf();
        var column = 0;
        for (index in 0...line.length) {
            var character = line.charAt(index);
            if (character == "\t") {
                var spaces = 4 - (column % 4);
                for (_ in 0...spaces) {
                    output.add(" ");
                }
                column += spaces;
            } else {
                output.add(character);
                column++;
            }
        }
        return output.toString();
    }

    static function normalizeLabel(label:String):String {
        return ~/\s+/g.replace(label.trim(), " ").toLowerCase();
    }

    static function isBlank(line:String):Bool {
        return line.trim() == "";
    }

    static function indentOf(line:String):Int {
        var count = 0;
        while (count < line.length && line.charAt(count) == " ") {
            count++;
        }
        return count;
    }

    function parseBlocks(lines:Array<String>):Array<Block> {
        var blocks:Array<Block> = [];
        var index = 0;
        while (index < lines.length) {
            var line = lines[index];
            if (isBlank(line)) {
                index++;
                continue;
            }
            if (fence.match(line)) {
                var indent = fence.matched(1).length;
                var marker = fence.matched(2);
                var language = fence.matched(3).trim().split(" ")[0];
                var body:Array<String> = [];
                index++;
                while (index < lines.length) {
                    var current = lines[index];
                    var trimmed = current.ltrim();
                    if (indentOf(current) < 4
                        && trimmed.startsWith(marker)
                        && trimmed.substr(marker.length).trim() == ""
                        && trimmed.charAt(0) == marker.charAt(0)) {
                        index++;
                        break;
                    }
                    body.push(removeIndent(current, indent));
                    index++;
                }
                blocks.push(Code(language, body.join("\n") + (body.length > 0 ? "\n" : "")));
                continue;
            }
            if (indentOf(line) >= 4) {
                var body:Array<String> = [];
                while (index < lines.length
                    && (isBlank(lines[index]) || indentOf(lines[index]) >= 4)) {
                    body.push(isBlank(lines[index]) ? "" : lines[index].substr(4));
                    index++;
                }
                while (body.length > 0 && body[body.length - 1] == "") {
                    body.pop();
                }
                blocks.push(Code("", body.join("\n") + "\n"));
                continue;
            }
            if (atxHeading.match(line)) {
                var text = atxHeading.matched(2);
                blocks.push(Heading(atxHeading.matched(1).length, text == null ? "" : text.trim()));
                index++;
                continue;
            }
            if (rule.match(line)) {
                blocks.push(Rule);
                index++;
                continue;
            }
            if (line.ltrim().startsWith(">")) {
                var quoted:Array<String> = [];
                while (index < lines.length && !isBlank(lines[index])) {
                    var current = lines[index];
                    var trimmed = current.ltrim();
                    if (trimmed.startsWith(">")) {
                        var rest = trimmed.substr(1);
                        quoted.push(rest.startsWith(" ") ? rest.substr(1) : rest);
                    } else if (quoted.length > 0 && !startsBlock(current)) {
                        quoted.push(current);
                    } else {
                        break;
                    }
                    index++;
                }
                blocks.push(Quote(parseBlocks(quoted)));
                continue;
            }
            if (bullet.match(line) || ordered.match(line)) {
                index = parseList(lines, index, blocks);
                continue;
            }
            if (index + 1 < lines.length
                && line.indexOf("|") >= 0
                && tableDelimiter.match(lines[index + 1])
                && lines[index + 1].indexOf("-") >= 0) {
                var header = cells(line);
                var alignments = [for (cell in cells(lines[index + 1])) alignment(cell)];
                if (header.length == alignments.length) {
                    index += 2;
                    var rows:Array<Array<String>> = [];
                    while (index < lines.length && !isBlank(lines[index])
                        && lines[index].indexOf("|") >= 0) {
                        var row = cells(lines[index]);
                        while (row.length < header.length) {
                            row.push("");
                        }
                        rows.push(row.slice(0, header.length));
                        index++;
                    }
                    blocks.push(Table(header, alignments, rows));
                    continue;
                }
            }
            var paragraph:Array<String> = [line.ltrim()];
            index++;
            var heading = 0;
            while (index < lines.length && !isBlank(lines[index])) {
                var current = lines[index];
                if (setextOne.match(current)) {
                    heading = 1;
                    index++;
                    break;
                }
                if (setextTwo.match(current)) {
                    heading = 2;
                    index++;
                    break;
                }
                if (startsBlock(current)) {
                    break;
                }
                paragraph.push(current.ltrim());
                index++;
            }
            if (heading > 0) {
                blocks.push(Heading(heading, paragraph.join("\n").trim()));
            } else {
                blocks.push(Paragraph(paragraph));
            }
        }
        return blocks;
    }

    static function removeIndent(line:String, indent:Int):String {
        var count = 0;
        while (count < indent && count < line.length && line.charAt(count) == " ") {
            count++;
        }
        return line.substr(count);
    }

    /** Whether a line interrupts a paragraph. **/
    static function startsBlock(line:String):Bool {
        if (atxHeading.match(line) || rule.match(line) || fence.match(line)) {
            return true;
        }
        var trimmed = line.ltrim();
        if (trimmed.startsWith(">")) {
            return true;
        }
        if (bullet.match(line) && bullet.matched(4).trim() != "") {
            return true;
        }
        if (ordered.match(line) && ordered.matched(2) == "1" && ordered.matched(5).trim() != "") {
            return true;
        }
        return false;
    }

    function parseList(lines:Array<String>, start:Int, blocks:Array<Block>):Int {
        var isOrdered = !bullet.match(lines[start]) && ordered.match(lines[start]);
        var first = 1;
        var markerChar = "";
        if (isOrdered) {
            ordered.match(lines[start]);
            first = Std.parseInt(ordered.matched(2));
            markerChar = ordered.matched(3);
        } else {
            bullet.match(lines[start]);
            markerChar = bullet.matched(2);
        }
        var items:Array<ListItem> = [];
        var loose = false;
        var index = start;
        var sawBlank = false;
        while (index < lines.length) {
            var line = lines[index];
            var contentIndent = 0;
            var firstLine = "";
            if (isOrdered
                && ordered.match(line)
                && ordered.matched(3) == markerChar
                && !bullet.match(line)) {
                var spacing = ordered.matched(4).length;
                contentIndent = ordered.matched(1).length
                    + ordered.matched(2).length
                    + 1
                    + (spacing == 0 || spacing > 4 ? 1 : spacing);
                firstLine = ordered.matched(5);
            } else if (!isOrdered
                && bullet.match(line)
                && bullet.matched(2) == markerChar
                && !rule.match(line)) {
                var spacing = bullet.matched(3).length;
                contentIndent = bullet.matched(1).length
                    + 1
                    + (spacing == 0 || spacing > 4 ? 1 : spacing);
                firstLine = bullet.matched(4);
            } else {
                break;
            }
            if (sawBlank) {
                loose = true;
            }
            var itemLines:Array<String> = [firstLine];
            index++;
            sawBlank = false;
            var blankInside = false;
            while (index < lines.length) {
                var current = lines[index];
                if (isBlank(current)) {
                    itemLines.push("");
                    sawBlank = true;
                    index++;
                    continue;
                }
                if (indentOf(current) >= contentIndent) {
                    if (sawBlank) {
                        blankInside = true;
                    }
                    itemLines.push(current.substr(contentIndent));
                    sawBlank = false;
                    index++;
                    continue;
                }
                if (!sawBlank
                    && !startsBlock(current)
                    && !bullet.match(current)
                    && !ordered.match(current)) {
                    itemLines.push(current.ltrim());
                    index++;
                    continue;
                }
                break;
            }
            while (itemLines.length > 0 && itemLines[itemLines.length - 1] == "") {
                itemLines.pop();
            }
            if (blankInside) {
                loose = true;
            }
            var taskState:Null<Bool> = null;
            if (itemLines.length > 0 && task.match(itemLines[0])) {
                taskState = task.matched(1) != " ";
                itemLines[0] = task.matched(2);
            }
            items.push(new ListItem(parseBlocks(itemLines), taskState));
        }
        blocks.push(ListBlock(isOrdered, first, items, loose));
        return index;
    }

    static function cells(line:String):Array<String> {
        var text = line.trim();
        if (text.startsWith("|")) {
            text = text.substr(1);
        }
        if (text.endsWith("|") && !text.endsWith("\\|")) {
            text = text.substr(0, text.length - 1);
        }
        var result:Array<String> = [];
        var current = new StringBuf();
        var index = 0;
        var inCode = false;
        while (index < text.length) {
            var character = text.charAt(index);
            if (character == "\\" && index + 1 < text.length && text.charAt(index + 1) == "|") {
                current.add("|");
                index += 2;
                continue;
            }
            if (character == "`") {
                inCode = !inCode;
            }
            if (character == "|" && !inCode) {
                result.push(current.toString().trim());
                current = new StringBuf();
            } else {
                current.add(character);
            }
            index++;
        }
        result.push(current.toString().trim());
        return result;
    }

    static function alignment(cell:String):String {
        var trimmed = cell.trim();
        var left = trimmed.startsWith(":");
        var right = trimmed.endsWith(":");
        return left && right ? "center" : right ? "right" : left ? "left" : "";
    }

    function blocksHtml(blocks:Array<Block>, output:StringBuf, tight:Bool):Void {
        var first = true;
        for (block in blocks) {
            if (!first) {
                output.add("\n");
            }
            first = false;
            blockHtml(block, output, tight);
        }
    }

    function blockHtml(block:Block, output:StringBuf, tight:Bool):Void {
        switch block {
            case Heading(level, text):
                var tag = level == 1 ? "h2" : 'h${level}';
                var inner = inlineHtml(text);
                var id = slug(plainText(inner));
                output.add('<${tag} id="${escape(id)}">${inner}</${tag}>');
            case Paragraph(lines):
                var inner = inlineHtml(lines.join("\n"));
                if (tight) {
                    output.add(inner);
                } else if (isImageOnly(inner)) {
                    output.add('<figure class="content-inline-image">${inner}</figure>');
                } else if (inner.trim() != "") {
                    output.add('<p>${inner}</p>');
                }
            case Code(language, text):
                var language = language == "" ? "" : ' class="language-${escape(language)}"';
                output.add('<pre><code${language}>${escape(text)}</code></pre>');
            case Quote(blocks):
                output.add("<blockquote>\n");
                blocksHtml(blocks, output, false);
                output.add("\n</blockquote>");
            case ListBlock(isOrdered, start, items, loose):
                var tag = isOrdered ? "ol" : "ul";
                var hasTasks = false;
                for (item in items) {
                    if (item.task != null) {
                        hasTasks = true;
                    }
                }
                var attributes = isOrdered && start != 1 ? ' start="${start}"' : "";
                if (hasTasks) {
                    attributes += ' class="contains-task-list"';
                }
                output.add('<${tag}${attributes}>\n');
                for (item in items) {
                    if (item.task != null) {
                        output.add('<li class="task-list-item"><input type="checkbox" disabled${item.task ? " checked" : ""}> ');
                    } else {
                        output.add("<li>");
                    }
                    if (loose) {
                        output.add("\n");
                    }
                    blocksHtml(item.blocks, output, !loose);
                    if (loose) {
                        output.add("\n");
                    }
                    output.add("</li>\n");
                }
                output.add('</${tag}>');
            case Rule:
                output.add("<hr>");
            case Table(header, alignments, rows):
                output.add('<div class="markdown-table"><table>\n<thead>\n<tr>\n');
                for (index in 0...header.length) {
                    output.add('<th${align(alignments[index])}>${inlineHtml(header[index])}</th>\n');
                }
                output.add("</tr>\n</thead>\n");
                if (rows.length > 0) {
                    output.add("<tbody>\n");
                    for (row in rows) {
                        output.add("<tr>\n");
                        for (index in 0...row.length) {
                            output.add('<td${align(alignments[index])}>${inlineHtml(row[index])}</td>\n');
                        }
                        output.add("</tr>\n");
                    }
                    output.add("</tbody>\n");
                }
                output.add("</table></div>");
        }
    }

    static function align(alignment:String):String {
        return alignment == "" ? "" : ' style="text-align:${alignment}"';
    }

    static function isImageOnly(html:String):Bool {
        if (html.indexOf("<img ") < 0) {
            return false;
        }
        var stripped = ~/<img [^>]*>/g.replace(html, "");
        return stripped.trim() == "";
    }

    static function plainText(html:String):String {
        return StringTools.htmlUnescape(~/<[^>]*>/g.replace(html, ""));
    }

    /** GitHub-style heading ids with the `content-` prefix; repeats get a number. **/
    function slug(text:String):String {
        var lowered = text.toLowerCase();
        var output = new StringBuf();
        for (index in 0...lowered.length) {
            var code = StringTools.fastCodeAt(lowered, index);
            var keep = (code >= "a".code && code <= "z".code)
                || (code >= "0".code && code <= "9".code)
                || code == "-".code
                || code == "_".code
                || code > 0x7F;
            if (code == " ".code) {
                output.add("-");
            } else if (keep) {
                output.addChar(code);
            }
        }
        var base = output.toString();
        var count = slugs.get(base);
        var result = base;
        if (count != null) {
            var next = count;
            do {
                next++;
                result = '${base}-${next}';
            } while (slugs.exists(result));
            slugs.set(base, next);
        }
        slugs.set(result, 0);
        if (!slugs.exists(base)) {
            slugs.set(base, 0);
        }
        return 'content-${result}';
    }

    function inlineHtml(text:String):String {
        var parser = new InlineParser(text, definitions, images);
        return parser.parse();
    }

    public static function escape(text:String):String {
        return StringTools.htmlEscape(text, true);
    }

    public static function allowedImage(url:String):Bool {
        return mediaImage.match(url);
    }

    public static function safeLink(url:String):Null<String> {
        var trimmed = url.trim();
        var colon = trimmed.indexOf(":");
        if (colon < 0) {
            return trimmed;
        }
        var slash = trimmed.indexOf("/");
        var question = trimmed.indexOf("?");
        var hash = trimmed.indexOf("#");
        for (position in [slash, question, hash]) {
            if (position >= 0 && position < colon) {
                return trimmed;
            }
        }
        var scheme = trimmed.substr(0, colon).toLowerCase();
        return
            ["http", "https", "mailto", "tel", "irc", "ircs", "xmpp"].indexOf(scheme) >= 0 ? trimmed : null;
    }

    public static function autolink():EReg {
        return autolinkUrl;
    }

    public static function emailPattern():EReg {
        return email;
    }
}

private class Delimiter {
    public final character:String;
    public var count:Int;
    public final canOpen:Bool;
    public final canClose:Bool;
    public final index:Int;
    public var active = true;
    public var openTags = "";
    public var closeTags = "";

    public function new(character:String, count:Int, canOpen:Bool, canClose:Bool, index:Int) {
        this.character = character;
        this.count = count;
        this.canOpen = canOpen;
        this.canClose = canClose;
        this.index = index;
    }
}

/** Inline Markdown: code, emphasis, strikethrough, links, images, autolinks and breaks. */
private class InlineParser {
    static final punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
    static final entity = ~/^&(?:#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});/;

    final text:String;
    final definitions:Map<String, LinkDefinition>;
    final images:Null<Array<String>>;
    final pieces:Array<String> = [];
    final delimiters:Array<Delimiter> = [];

    public function new(text:String, definitions:Map<String, LinkDefinition>,
            ?images:Array<String>) {
        this.text = text;
        this.definitions = definitions;
        this.images = images;
    }

    public function parse():String {
        var index = 0;
        var buffer = new StringBuf();
        function flush() {
            var value = buffer.toString();
            if (value != "") {
                pieces.push(value);
            }
            buffer = new StringBuf();
        }
        while (index < text.length) {
            var character = text.charAt(index);
            switch character {
                case "\\":
                    if (index + 1 < text.length) {
                        var next = text.charAt(index + 1);
                        if (next == "\n") {
                            flush();
                            pieces.push("<br>\n");
                            index += 2;
                            continue;
                        }
                        if (punctuation.indexOf(next) >= 0) {
                            buffer.add(Markdown.escape(next));
                            index += 2;
                            continue;
                        }
                    }
                    buffer.add("\\");
                    index++;
                case "`":
                    var run = runLength(index, "`");
                    var close = findBackticks(index + run, run);
                    if (close < 0) {
                        buffer.add(Markdown.escape(text.substr(index, run)));
                        index += run;
                        continue;
                    }
                    var code = text.substring(index + run, close).replace("\n", " ");
                    if (code.length > 2
                        && code.startsWith(" ")
                        && code.endsWith(" ")
                        && code.trim() != "") {
                        code = code.substr(1, code.length - 2);
                    }
                    flush();
                    pieces.push('<code>${Markdown.escape(code)}</code>');
                    index = close + run;
                case "*" | "_" | "~":
                    var run = runLength(index, character);
                    if (character == "~" && run > 2) {
                        buffer.add(text.substr(index, run));
                        index += run;
                        continue;
                    }
                    var before = index > 0 ? text.charAt(index - 1) : " ";
                    var after = index + run < text.length ? text.charAt(index + run) : " ";
                    var leftFlanking = !isSpace(after)
                        && (!isPunctuation(after) || isSpace(before) || isPunctuation(before));
                    var rightFlanking = !isSpace(before)
                        && (!isPunctuation(before) || isSpace(after) || isPunctuation(after));
                    var canOpen = character == "_" ? leftFlanking
                        && (!rightFlanking || isPunctuation(before)) : leftFlanking;
                    var canClose = character == "_" ? rightFlanking
                        && (!leftFlanking || isPunctuation(after)) : rightFlanking;
                    flush();
                    delimiters.push(new Delimiter(character, run, canOpen, canClose,
                        pieces.length));
                    pieces.push(text.substr(index, run));
                    index += run;
                case "!" if (index + 1 < text.length && text.charAt(index + 1) == "["):
                    var link = parseLink(index + 1);
                    if (link == null) {
                        buffer.add("!");
                        index++;
                        continue;
                    }
                    flush();
                    var url = link.url.trim();
                    if (images != null) {
                        images.push(url);
                    }
                    if (Markdown.allowedImage(url)) {
                        var alt = StringTools.htmlUnescape(~/<[^>]*>/g.replace(link.label, ""));
                        pieces.push('<img src="${Markdown.escape(url)}" alt="${Markdown.escape(alt)}" loading="lazy">');
                    }
                    index = link.end;
                case "[":
                    var link = parseLink(index);
                    if (link == null) {
                        buffer.add("[");
                        index++;
                        continue;
                    }
                    flush();
                    pieces.push(anchor(link.url, link.title, link.label));
                    index = link.end;
                case "<":
                    var close = text.indexOf(">", index);
                    var inner = close < 0 ? "" : text.substring(index + 1, close);
                    if (close > 0 && ~/^[A-Za-z][A-Za-z0-9+.-]{1,31}:[^\s<>]*$/.match(inner)) {
                        flush();
                        pieces.push(anchor(inner, null, Markdown.escape(inner)));
                        index = close + 1;
                        continue;
                    }
                    if (close > 0
                        && ~/^[A-Za-z0-9._+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/.match(inner)) {
                        flush();
                        pieces.push(anchor('mailto:${inner}', null, Markdown.escape(inner)));
                        index = close + 1;
                        continue;
                    }
                    buffer.add("&lt;");
                    index++;
                case "&":
                    var rest = text.substr(index, 40);
                    if (entity.match(rest)) {
                        var raw = entity.matched(0);
                        buffer.add(Markdown.escape(StringTools.htmlUnescape(raw)));
                        index += raw.length;
                    } else {
                        buffer.add("&amp;");
                        index++;
                    }
                case "\n":
                    var content = buffer.toString();
                    if (content.endsWith("  ")) {
                        buffer = new StringBuf();
                        buffer.add(content.rtrim());
                        flush();
                        pieces.push("<br>\n");
                    } else {
                        buffer = new StringBuf();
                        buffer.add(content.rtrim());
                        buffer.add("\n");
                    }
                    index++;
                default:
                    var literal = autolinkLiteral(index);
                    if (literal != null) {
                        flush();
                        pieces.push(literal.html);
                        index = literal.end;
                        continue;
                    }
                    buffer.add(Markdown.escape(character));
                    index++;
            }
        }
        flush();
        resolveEmphasis();
        return pieces.join("");
    }

    static function isSpace(character:String):Bool {
        return character == " " || character == "\n" || character == "\t" || character == "";
    }

    static function isPunctuation(character:String):Bool {
        return punctuation.indexOf(character) >= 0;
    }

    function runLength(start:Int, character:String):Int {
        var end = start;
        while (end < text.length && text.charAt(end) == character) {
            end++;
        }
        return end - start;
    }

    function findBackticks(from:Int, run:Int):Int {
        var index = from;
        while (index < text.length) {
            if (text.charAt(index) == "`") {
                var length = runLength(index, "`");
                if (length == run) {
                    return index;
                }
                index += length;
            } else {
                index++;
            }
        }
        return -1;
    }

    function anchor(url:String, title:Null<String>, label:String):String {
        var safe = Markdown.safeLink(url);
        var href = safe == null ? "" : safe;
        var external = ~/^https?:\/\//i.match(href);
        var attributes = new StringBuf();
        attributes.add('href="${Markdown.escape(href)}"');
        if (title != null && title != "") {
            attributes.add(' title="${Markdown.escape(title)}"');
        }
        if (external) {
            attributes.add(' target="_blank" rel="noopener noreferrer"');
        }
        return '<a ${attributes.toString()}>${label}</a>';
    }

    /** `[label](url "title")`, `[label][ref]`, `[label][]` or `[label]` starting at `[`. **/
    function parseLink(start:Int):Null<{
        label:String,
        url:String,
        title:Null<String>,
        end:Int
    }> {
        var depth = 0;
        var index = start;
        var close = -1;
        while (index < text.length) {
            var character = text.charAt(index);
            if (character == "\\") {
                index += 2;
                continue;
            }
            if (character == "`") {
                var run = runLength(index, "`");
                var end = findBackticks(index + run, run);
                index = end < 0 ? index + run : end + run;
                continue;
            }
            if (character == "[") {
                depth++;
            } else if (character == "]") {
                depth--;
                if (depth == 0) {
                    close = index;
                    break;
                }
            }
            index++;
        }
        if (close < 0) {
            return null;
        }
        var labelSource = text.substring(start + 1, close);
        var label = new InlineParser(labelSource, definitions, images).parse();
        var next = close + 1;
        if (next < text.length && text.charAt(next) == "(") {
            var destination = parseDestination(next + 1);
            if (destination != null) {
                return {
                    label: label,
                    url: destination.url,
                    title: destination.title,
                    end: destination.end
                };
            }
        }
        var reference = labelSource;
        var end = next;
        if (next < text.length && text.charAt(next) == "[") {
            var referenceClose = text.indexOf("]", next);
            if (referenceClose > 0) {
                var inner = text.substring(next + 1, referenceClose);
                if (inner.trim() != "") {
                    reference = inner;
                }
                end = referenceClose + 1;
            }
        }
        var found = definitions.get(~/\s+/g.replace(reference.trim(), " ").toLowerCase());
        if (found == null) {
            return null;
        }
        return {
            label: label,
            url: found.url,
            title: found.title,
            end: end
        };
    }

    function parseDestination(start:Int):Null<{url:String, title:Null<String>, end:Int}> {
        var index = start;
        while (index < text.length && isSpace(text.charAt(index))) {
            index++;
        }
        var url = new StringBuf();
        if (index < text.length && text.charAt(index) == "<") {
            var close = text.indexOf(">", index);
            if (close < 0) {
                return null;
            }
            url.add(text.substring(index + 1, close));
            index = close + 1;
        } else {
            var depth = 0;
            while (index < text.length) {
                var character = text.charAt(index);
                if (character == "\\" && index + 1 < text.length) {
                    url.add(text.charAt(index + 1));
                    index += 2;
                    continue;
                }
                if (isSpace(character)) {
                    break;
                }
                if (character == "(") {
                    depth++;
                } else if (character == ")") {
                    if (depth == 0) {
                        break;
                    }
                    depth--;
                }
                url.add(character);
                index++;
            }
        }
        while (index < text.length && isSpace(text.charAt(index))) {
            index++;
        }
        var title:Null<String> = null;
        if (index < text.length) {
            var opener = text.charAt(index);
            var closer = opener == "(" ? ")" : opener;
            if (opener == '"' || opener == "'" || opener == "(") {
                var close = text.indexOf(closer, index + 1);
                if (close < 0) {
                    return null;
                }
                title = text.substring(index + 1, close);
                index = close + 1;
                while (index < text.length && isSpace(text.charAt(index))) {
                    index++;
                }
            }
        }
        if (index >= text.length || text.charAt(index) != ")") {
            return null;
        }
        return {url: StringTools.htmlUnescape(url.toString()), title: title, end: index + 1};
    }

    function autolinkLiteral(index:Int):Null<{html:String, end:Int}> {
        if (index > 0) {
            var before = text.charAt(index - 1);
            if (~/[A-Za-z0-9]/.match(before)) {
                return null;
            }
        }
        var rest = text.substr(index, 2048);
        var first = rest.charAt(0);
        if (first == "h" || first == "H" || first == "w" || first == "W") {
            var pattern = Markdown.autolink();
            if (pattern.match(rest)) {
                var raw = pattern.matched(0);
                raw = balanceParentheses(raw);
                var href = StringTools.startsWith(raw.toLowerCase(),
                    "www.") ? 'http://${raw}' : raw;
                return {html: anchor(href, null, Markdown.escape(raw)), end: index + raw.length};
            }
        }
        if (~/[A-Za-z0-9._+-]/.match(first)) {
            var pattern = Markdown.emailPattern();
            if (pattern.match(rest) && rest.indexOf("@") > 0) {
                var raw = pattern.matched(0);
                if (raw.indexOf("@") > 0 && !StringTools.endsWith(raw, ".")) {
                    return {
                        html: anchor('mailto:${raw}', null, Markdown.escape(raw)),
                        end: index + raw.length
                    };
                }
            }
        }
        return null;
    }

    static function balanceParentheses(url:String):String {
        var result = url;
        while (StringTools.endsWith(result, ")")) {
            var opened = result.split("(").length - 1;
            var closed = result.split(")").length - 1;
            if (closed <= opened) {
                break;
            }
            result = result.substr(0, result.length - 1);
        }
        return result;
    }

    /** Matches emphasis and strikethrough delimiters, innermost first, like CommonMark. **/
    function resolveEmphasis():Void {
        var index = 0;
        while (index < delimiters.length) {
            var closer = delimiters[index];
            if (!closer.active || !closer.canClose || closer.count == 0) {
                index++;
                continue;
            }
            var opener:Null<Delimiter> = null;
            var position = index - 1;
            while (position >= 0) {
                var candidate = delimiters[position];
                if (candidate.active
                    && candidate.character == closer.character
                    && candidate.canOpen
                    && candidate.count > 0) {
                    var oddMatch = (candidate.canClose || closer.canOpen)
                        && (candidate.count
                            + closer.count) % 3 == 0
                            && (candidate.count % 3 != 0 || closer.count % 3 != 0);
                    var tildeMatch = closer.character != "~" || candidate.count == closer.count;
                    if (!oddMatch && tildeMatch) {
                        opener = candidate;
                        break;
                    }
                }
                position--;
            }
            if (opener == null) {
                index++;
                continue;
            }
            var tag:String;
            var used:Int;
            if (closer.character == "~") {
                tag = "del";
                used = closer.count;
            } else if (opener.count >= 2 && closer.count >= 2) {
                tag = "strong";
                used = 2;
            } else {
                tag = "em";
                used = 1;
            }
            opener.count -= used;
            closer.count -= used;
            opener.openTags = '<${tag}>' + opener.openTags;
            closer.closeTags = closer.closeTags + '</${tag}>';
            // Delimiters between a matched pair stay text.
            for (between in position + 1...index) {
                delimiters[between].active = false;
            }
            if (closer.count == 0) {
                index++;
            }
        }
        for (delimiter in delimiters) {
            var literal = new StringBuf();
            for (_ in 0...delimiter.count) {
                literal.add(delimiter.character);
            }
            pieces[delimiter.index] = '${delimiter.closeTags}${literal.toString()}${delimiter.openTags}';
        }
    }
}
