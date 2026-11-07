package hx.press.themes;

#if jvm
import haxe.Exception;
import haxe.Json;
import haxe.crypto.Base64;
import haxe.crypto.Sha1;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.Path;
import hx.press.validation.Port;
import hx.well.facades.Environment;
import hx.well.facades.Storage;
import hx.well.internal.SecureToken;
import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.File;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.Process;
import java.lang.ProcessBuilder;
import java.lang.ProcessBuilder.ProcessBuilder_Redirect;
import java.lang.System;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.file.Files;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.concurrent.TimeUnit;
import jvm.thread.VirtualThread;
import sys.FileSystem;
import sys.thread.Lock;
import sys.thread.Mutex;

typedef PreviewViewport = {
    var width:Int;
    var height:Int;
    var mobile:Bool;
}

typedef PreviewLink = {
    var href:String;
    var text:String;
}

typedef PreviewCapture = {
    /** Base64 JPEG. */
    var image:String;

    /** HTTP status of the Document response, 0 if unknown. */
    var status:Int;

    var title:String;

    /** Page scroll height. */
    var height:Int;

    var headings:Array<String>;
    var links:Array<PreviewLink>;
}

/**
    Captures theme previews in a headless Chrome or Chromium on the site's host, over the
    DevTools protocol, so an AI can look at the design it edits. The browser starts on the
    first capture and stops after two idle minutes.
**/
class ThemePreviewBrowser {
    static inline var IDLE_SECONDS = 120;
    static inline var MAX_HEIGHT = 8000;
    static inline var LOAD_SECONDS = 20;
    // A cold start on a busy host can take well over ten seconds; Puppeteer allows 30.
    static inline var START_SECONDS = 30;
    static inline var MISSING_BROWSER = "Theme previews need Chrome or Chromium on the server. Install one, or set HAXEPRESS_CHROME to its executable.";

    /**
        Browsers that relaunch themselves, such as Brave or Edge, are not used: a relaunched
        process would outlive the site.
    **/
    static final installedBrowsers = [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "/usr/bin/chrome-headless-shell",
        "/usr/bin/google-chrome",
        "/usr/bin/google-chrome-stable",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
        "/snap/bin/chromium"
    ];

    // Waits for the image and font loads a lazy page starts, then for one painted frame.
    static inline var SETTLE_SCRIPT = "document.querySelectorAll('img[loading=\"lazy\"]').forEach((image) => { image.loading = 'eager'; });
        Promise.race([
          Promise.all([
            document.fonts ? document.fonts.ready : null,
            ...[...document.images].filter((image) => !image.complete).map(
              (image) => new Promise((done) => { image.onload = image.onerror = done; })
            )
          ]),
          new Promise((done) => setTimeout(done, 4000))
        ]).then(() => new Promise((done) => requestAnimationFrame(() => setTimeout(done, 100))))";

    static inline var SUMMARY_SCRIPT = "({
          title: document.title,
          height: Math.ceil(Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)),
          headings: [...document.querySelectorAll('h1, h2, h3')].map((heading) => heading.textContent.trim().replace(/\\s+/g, ' ').slice(0, 120)).filter(Boolean).slice(0, 30),
          links: [...new Map([...document.querySelectorAll('a[href]')].map((link) => {
            const target = new URL(link.href, location.href);
            return [target.pathname + target.search, (link.textContent || link.getAttribute('aria-label') || '').trim().replace(/\\s+/g, ' ').slice(0, 80)];
          }).filter(([href]) => href)).entries()].slice(0, 60).map(([href, text]) => ({ href, text }))
        })";

    static final captures = new Mutex();
    static final state = new Mutex();
    static var running:Null<PreviewBrowserProcess> = null;
    static var idleGeneration = 0;
    static var browserFound:Null<Bool> = null;

    /** Whether a usable browser executable exists; the answer is kept for the process lifetime. */
    public static function available():Bool {
        if (browserFound == null) {
            browserFound = findBrowser() != null;
        }
        return browserFound;
    }

    /**
        Loads `url` with `headers` at a viewport size and returns a JPEG of the first screen,
        or of the whole page up to 8,000 pixels, with the page's title, HTTP status, height and
        links. One capture runs at a time.
    **/
    public static function capture(url:String, headers:Map<String, String>,
            viewport:PreviewViewport, fullPage:Bool):PreviewCapture {
        captures.acquire();
        try {
            var result = captureNow(url, headers, viewport, fullPage);
            scheduleIdleStop();
            captures.release();
            return result;
        } catch (error:Exception) {
            scheduleIdleStop();
            captures.release();
            if (Std.isOfType(error, PreviewFailure)) {
                throw error;
            }
            throw new Exception('The preview failed: ${error.message}', error);
        }
    }

    /** Stops the preview browser, as the site does when it shuts down. */
    public static function stop():Void {
        state.acquire();
        idleGeneration++;
        var current = running;
        running = null;
        state.release();
        if (current != null) {
            current.shutdown();
        }
    }

    /**
        The configured browser, else Chrome's headless shell cached by Puppeteer, else an
        installed Chrome or Chromium.
    **/
    static function findBrowser():Null<String> {
        var configured = setting("HAXEPRESS_CHROME");
        if (configured != null && configured != "") {
            return FileSystem.exists(configured) ? configured : null;
        }
        var home = Sys.getEnv("HOME") ?? System.getProperty("user.home");
        if (home != null && home != "") {
            var cache = Path.join([home, ".cache", "puppeteer", "chrome-headless-shell"]);
            var shell = cachedShell(cache);
            if (shell != null) {
                return shell;
            }
        }
        for (path in installedBrowsers) {
            if (FileSystem.exists(path)) {
                return path;
            }
        }
        return null;
    }

    static function cachedShell(cache:String):Null<String> {
        if (!FileSystem.exists(cache) || !FileSystem.isDirectory(cache)) {
            return null;
        }
        var versions = FileSystem.readDirectory(cache);
        versions.sort(Reflect.compare);
        versions.reverse();
        for (version in versions) {
            var versionPath = Path.join([cache, version]);
            if (!FileSystem.isDirectory(versionPath)) {
                continue;
            }
            for (platform in FileSystem.readDirectory(versionPath)) {
                var shell = Path.join([versionPath, platform, "chrome-headless-shell"]);
                if (FileSystem.exists(shell)) {
                    return shell;
                }
            }
        }
        return null;
    }

    /** A site setting from `.env`, else from the process environment. */
    static function setting(name:String):Null<String> {
        var value:Null<String> = null;
        try {
            value = Environment.env(name);
        } catch (_:Dynamic) {}
        if (value == null || value == "") {
            value = Sys.getEnv(name);
        }
        return value;
    }

    static function scheduleIdleStop():Void {
        state.acquire();
        idleGeneration++;
        var generation = idleGeneration;
        var active = running != null;
        state.release();
        if (!active) {
            return;
        }
        // A virtual thread never keeps the JVM running.
        VirtualThread.create(() -> {
            Sys.sleep(IDLE_SECONDS);
            state.acquire();
            var idle = generation == idleGeneration ? running : null;
            if (idle != null) {
                running = null;
            }
            state.release();
            if (idle != null) {
                idle.shutdown();
            }
        }).start();
    }

    static function devTools():DevToolsConnection {
        state.acquire();
        idleGeneration++;
        var generation = idleGeneration;
        var current = running;
        state.release();
        if (current != null && current.usable()) {
            return current.tools;
        }
        if (current != null) {
            state.acquire();
            var stale = running == current;
            if (stale) {
                running = null;
            }
            state.release();
            if (stale) {
                current.shutdown();
            }
        }
        var launched = launch();
        state.acquire();
        // A stop() during the launch wins; the site may be shutting down.
        var kept = generation == idleGeneration;
        if (kept) {
            running = launched;
        }
        state.release();
        if (!kept) {
            launched.shutdown();
            throw new PreviewFailure("The preview browser stopped while starting.");
        }
        return launched.tools;
    }

    static function launch():PreviewBrowserProcess {
        var executable = findBrowser();
        if (executable == null) {
            throw new PreviewFailure(MISSING_BROWSER);
        }
        PreviewBrowserProcess.removeStaleProfiles();
        var profile = PreviewBrowserProcess.createProfile();
        var command = browserCommand(executable, PreviewBrowserProcess.profilePath(profile));
        var builder = new ProcessBuilder(command);
        // Standard output is discarded; the JDK externs predate Redirect.DISCARD.
        builder.redirectOutput(ProcessBuilder_Redirect.to(new File(nullDevice())));
        var process:Process;
        try {
            process = builder.start();
        } catch (_:Dynamic) {
            PreviewBrowserProcess.removeProfile(profile);
            throw new PreviewFailure("The preview browser did not start.");
        }
        var browser = new PreviewBrowserProcess(process, profile);
        try {
            process.getOutputStream().close();
            var output = new BrowserOutput();
            var stderr = process.getErrorStream();
            VirtualThread.create(() -> output.drain(stderr)).start();
            if (!output.ready.wait(START_SECONDS)) {
                output.report('did not start in ${START_SECONDS} seconds');
                throw new PreviewFailure("The preview browser did not start.");
            }
            if (output.address == null) {
                output.report("stopped while starting");
                throw new PreviewFailure("The preview browser stopped while starting.");
            }
            browser.tools = DevToolsConnection.open(output.address);
        } catch (error:Exception) {
            browser.shutdown();
            throw error;
        }
        return browser;
    }

    static function nullDevice():String {
        var system = System.getProperty("os.name") ?? "";
        return StringTools.startsWith(system.toLowerCase(), "windows") ? "NUL" : "/dev/null";
    }

    static function browserCommand(executable:String, profile:String):ArrayList<String> {
        var shell = Path.withoutDirectory(executable) == "chrome-headless-shell";
        var flags = [executable];
        if (!shell) {
            flags.push("--headless=new");
        }
        flags = flags.concat([
            "--remote-debugging-port=0",
            '--user-data-dir=${profile}',
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-extensions",
            "--disable-background-networking",
            "--disable-sync",
            "--hide-scrollbars",
            "--mute-audio"
        ]);
        // Extra flags for hosts that need them, such as --no-sandbox in CI containers.
        var extraFlags = ~/\s+/g.split(setting("HAXEPRESS_CHROME_ARGS") ?? "");
        var hostFlags = extraFlags.filter(flag -> flag != "");
        flags = flags.concat(hostFlags);
        flags.push("about:blank");
        var command = new ArrayList<String>();
        for (flag in flags) {
            command.add(flag);
        }
        return command;
    }

    static function captureNow(url:String, headers:Map<String, String>, viewport:PreviewViewport,
            fullPage:Bool):PreviewCapture {
        var tools = devTools();
        var created:Dynamic = tools.send("Target.createTarget", {url: "about:blank"});
        var targetId:String = created.targetId;
        try {
            var result = captureTarget(tools, targetId, url, headers, viewport, fullPage);
            closeTarget(tools, targetId);
            return result;
        } catch (error:Exception) {
            closeTarget(tools, targetId);
            throw error;
        }
    }

    static function closeTarget(tools:DevToolsConnection, targetId:String):Void {
        try {
            tools.send("Target.closeTarget", {targetId: targetId});
        } catch (_:Dynamic) {}
    }

    static function captureTarget(tools:DevToolsConnection, targetId:String, url:String,
            headers:Map<String, String>, viewport:PreviewViewport, fullPage:Bool):PreviewCapture {
        var attached:Dynamic = tools.send("Target.attachToTarget", {
            targetId: targetId,
            flatten: true
        });
        var sessionId:String = attached.sessionId;
        var status = 0;
        var listener = tools.listen((method, params, session) -> {
            if (method == "Network.responseReceived" && session == sessionId
                && params.type == "Document") {
                var response:Dynamic = params.response;
                status = integer(response == null ? null : response.status);
            }
        });
        try {
            var page = loadPage(tools, sessionId, url, headers, viewport);
            var result = screenshot(tools, sessionId, page, viewport, fullPage);
            result.status = status;
            tools.unlisten(listener);
            return result;
        } catch (error:Exception) {
            tools.unlisten(listener);
            throw error;
        }
    }

    static function loadPage(tools:DevToolsConnection, sessionId:String, url:String,
            headers:Map<String, String>, viewport:PreviewViewport):Dynamic {
        var headerFields:Dynamic = {};
        if (headers != null) {
            for (name => value in headers) {
                Reflect.setField(headerFields, name, value);
            }
        }
        tools.send("Page.enable", {}, sessionId);
        tools.send("Network.enable", {}, sessionId);
        tools.send("Network.setExtraHTTPHeaders", {headers: headerFields}, sessionId);
        tools.send("Emulation.setDeviceMetricsOverride", {
            width: viewport.width,
            height: viewport.height,
            deviceScaleFactor: 1,
            mobile: viewport.mobile
        }, sessionId);
        tools.send("Emulation.setTouchEmulationEnabled", {enabled: viewport.mobile}, sessionId);
        var loaded = tools.expect("Page.loadEventFired", sessionId);
        try {
            var navigation:Dynamic = tools.send("Page.navigate", {url: url}, sessionId);
            var errorText:Null<String> = navigation.errorText;
            if (errorText != null && errorText != "") {
                throw new PreviewFailure('The preview could not load: ${errorText}');
            }
        } catch (error:Exception) {
            tools.forget(loaded);
            throw error;
        }
        if (!tools.await(loaded, LOAD_SECONDS)) {
            throw new PreviewFailure("The preview page did not finish loading in time.");
        }
        evaluate(tools, sessionId, SETTLE_SCRIPT);
        var page:Dynamic = evaluate(tools, sessionId, SUMMARY_SCRIPT);
        if (page == null) {
            throw new PreviewFailure("The preview page could not be read.");
        }
        return page;
    }

    static function screenshot(tools:DevToolsConnection, sessionId:String, page:Dynamic,
            viewport:PreviewViewport, fullPage:Bool):PreviewCapture {
        var pageHeight = integer(page.height);
        var tallest = pageHeight > viewport.height ? pageHeight : viewport.height;
        var height = fullPage ? (tallest < MAX_HEIGHT ? tallest : MAX_HEIGHT) : viewport.height;
        var shot:Dynamic = tools.send("Page.captureScreenshot", {
            format: "jpeg",
            quality: 78,
            captureBeyondViewport: fullPage,
            clip: {
                x: 0,
                y: 0,
                width: viewport.width,
                height: height,
                scale: 1
            }
        }, sessionId);
        var headingValues:Array<Dynamic> = page.headings ?? [];
        var headings = [for (heading in headingValues) Std.string(heading)];
        var linkValues:Array<Dynamic> = page.links ?? [];
        var links:Array<PreviewLink> = [
            for (link in linkValues)
                {href: Std.string(link.href), text: Std.string(link.text)}
        ];
        var title:Null<String> = page.title;
        return {
            image: shot.data,
            status: 0,
            title: title ?? "",
            height: pageHeight,
            headings: headings,
            links: links
        };
    }

    static function evaluate(tools:DevToolsConnection, sessionId:String,
            expression:String):Dynamic {
        var reply:Dynamic = tools.send("Runtime.evaluate", {
            expression: expression,
            awaitPromise: true,
            returnByValue: true
        }, sessionId);
        var remote:Dynamic = reply.result;
        return remote == null ? null : remote.value;
    }

    static function integer(value:Dynamic):Int {
        if (Std.isOfType(value, Int)) {
            return value;
        }
        if (Std.isOfType(value, Float)) {
            return Std.int(value);
        }
        return 0;
    }
}

/** A failure whose message is meant for the person or AI asking for the preview. */
private class PreviewFailure extends Exception {}

/** One running browser with its DevTools connection and temporary profile. */
private class PreviewBrowserProcess {
    static inline var PROFILE_DISK = "local";
    static inline var PROFILE_FOLDER = "preview-browser";

    public final process:Process;
    public final profile:String;
    public var tools:Null<DevToolsConnection> = null;

    public function new(process:Process, profile:String) {
        this.process = process;
        this.profile = profile;
    }

    /** Creates a temporary profile folder on the local disk and returns its disk path. */
    public static function createProfile():String {
        var profile = '${PROFILE_FOLDER}/${SecureToken.generate(16)}';
        if (!Storage.disk(PROFILE_DISK).makeDirectory(profile)) {
            throw new PreviewFailure("The preview browser could not create its profile folder.");
        }
        return profile;
    }

    /** The physical folder, for the browser's --user-data-dir flag only. */
    public static function profilePath(profile:String):String {
        return Storage.disk(PROFILE_DISK).path(profile);
    }

    public function usable():Bool {
        return tools != null && !tools.isClosed() && process.isAlive();
    }

    public function shutdown():Void {
        if (tools != null) {
            tools.close();
        }
        // The browser has nothing to save; a graceful exit can outlast the site's shutdown.
        // Its helper processes exit when it does.
        process.destroyForcibly();
        try {
            process.waitFor(5, TimeUnit.SECONDS);
        } catch (_:Dynamic) {}
        removeProfile(profile);
    }

    public static function removeProfile(profile:String):Void {
        try {
            var disk = Storage.disk(PROFILE_DISK);
            // A killed Chrome leaves its singleton links behind, and the disk refuses links.
            var folder = new File(disk.path(profile));
            var entries = folder.listFiles();
            if (entries != null) {
                for (index in 0...entries.length) {
                    var entry = entries[index];
                    if (Files.isSymbolicLink(entry.toPath())) {
                        entry.delete();
                    }
                }
            }
            disk.deleteDirectory(profile);
        } catch (_:Dynamic) {
            // The browser may still be removing its own files.
        }
    }

    /**
        Removes the profile folders earlier browsers left behind, such as one
        whose removal failed or a site that stopped without stopping its
        browser. Only one browser runs at a time, so before a launch every
        profile folder is stale.
    **/
    public static function removeStaleProfiles():Void {
        try {
            for (profile in Storage.disk(PROFILE_DISK).directories(PROFILE_FOLDER)) {
                removeProfile(profile);
            }
        } catch (_:Dynamic) {}
    }
}

/** Reads the browser's stderr until DevTools reports its address, then keeps draining it. */
private class BrowserOutput {
    static inline var REPORTED_CHARACTERS = 2000;

    public final ready = new Lock();
    public var address:Null<String> = null;

    /** What the browser has written so far, kept to explain a failed start. */
    var output = "";

    public function new() {}

    /** Logs why the browser did not start, with the end of what it wrote. */
    public function report(problem:String):Void {
        var written = StringTools.trim(output.substr(-REPORTED_CHARACTERS));
        var detail = written == "" ? "it wrote nothing" : 'it wrote:\n${written}';
        trace('The preview browser ${problem}; ${detail}');
    }

    public function drain(stream:InputStream):Void {
        var pattern = ~/DevTools listening on (ws:\/\/\S+)\s/;
        var buffer = Bytes.alloc(4096);
        var waiting = true;
        try {
            var count = stream.read(buffer.getData(), 0, buffer.length);
            while (count >= 0) {
                if (waiting && count > 0) {
                    output += buffer.getString(0, count);
                    if (pattern.match(output)) {
                        address = pattern.matched(1);
                        waiting = false;
                        ready.release();
                    } else if (output.length > 65536) {
                        output = output.substr(-REPORTED_CHARACTERS);
                    }
                }
                // The pipe must never fill, or the browser would stall.
                count = stream.read(buffer.getData(), 0, buffer.length);
            }
        } catch (_:Dynamic) {}
        if (waiting) {
            ready.release();
        }
    }
}

private typedef DevToolsCallback = (method:String, params:Dynamic, sessionId:Null<String>) -> Void;

private class DevToolsListener {
    public final callback:DevToolsCallback;

    public function new(callback:DevToolsCallback) {
        this.callback = callback;
    }
}

private class DevToolsReply {
    public final lock = new Lock();
    public var result:Dynamic = null;
    public var error:Null<String> = null;

    public function new() {}
}

private class DevToolsEvent {
    public final method:String;
    public final sessionId:String;
    public final lock = new Lock();
    public var fired = false;

    public function new(method:String, sessionId:String) {
        this.method = method;
        this.sessionId = sessionId;
    }
}

/** A DevTools protocol connection over a plain loopback WebSocket: commands with replies, and events. */
private class DevToolsConnection {
    static inline var CLOSED = "The browser closed.";
    static inline var REFUSED = "The browser did not accept a connection.";
    static inline var COMMAND_SECONDS = 30;
    static inline var CONNECT_MILLISECONDS = 5000;
    static inline var MAX_HEAD_BYTES = 16384;
    static inline var MAX_MESSAGE_BYTES = 64 * 1048576;
    static inline var WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    static inline var CONTINUATION = 0x0;
    static inline var TEXT = 0x1;
    static inline var BINARY = 0x2;
    static inline var CLOSE = 0x8;
    static inline var PING = 0x9;
    static inline var PONG = 0xA;
    static final random = new SecureRandom();

    final socket:Socket;
    final input:DataInputStream;
    final output:OutputStream;
    final guard = new Mutex();
    final writing = new Mutex();
    final pending:Map<Int, DevToolsReply> = [];
    var listeners:Array<DevToolsListener> = [];
    var expected:Array<DevToolsEvent> = [];
    var nextId = 0;
    var closed = false;

    function new(socket:Socket, input:DataInputStream, output:OutputStream) {
        this.socket = socket;
        this.input = input;
        this.output = output;
    }

    public static function open(address:String):DevToolsConnection {
        var pattern = ~/^ws:\/\/(\[[^\]]+\]|[^\/:]+):([0-9]+)(\/\S*)$/;
        if (!pattern.match(address)) {
            throw new PreviewFailure(REFUSED);
        }
        var host = pattern.matched(1);
        var port = Port.parse(pattern.matched(2));
        if (port == null) {
            throw new PreviewFailure(REFUSED);
        }
        var path = pattern.matched(3);
        var hostName = StringTools.startsWith(host, "[") ? host.substr(1, host.length - 2) : host;
        var socket = new Socket();
        try {
            socket.connect(new InetSocketAddress(hostName, port), CONNECT_MILLISECONDS);
            socket.setTcpNoDelay(true);
            socket.setSoTimeout(CONNECT_MILLISECONDS);
            var input = new DataInputStream(new BufferedInputStream(socket.getInputStream(),
                65536));
            var output = socket.getOutputStream();
            handshake(input, output, '${host}:${port}', path);
            socket.setSoTimeout(0);
            var connection = new DevToolsConnection(socket, input, output);
            VirtualThread.create(connection.read).start();
            return connection;
        } catch (_:Dynamic) {
            try {
                socket.close();
            } catch (_:Dynamic) {}
            throw new PreviewFailure(REFUSED);
        }
    }

    static function handshake(input:DataInputStream, output:OutputStream, host:String,
            path:String):Void {
        var key = Base64.encode(randomBytes(16));
        var requestLines = [
            'GET ${path} HTTP/1.1',
            'Host: ${host}',
            "Upgrade: websocket",
            "Connection: Upgrade",
            'Sec-WebSocket-Key: ${key}',
            "Sec-WebSocket-Version: 13"
        ];
        var requestHead = requestLines.join("\r\n");
        var request = '${requestHead}\r\n\r\n';
        var requestBytes = Bytes.ofString(request);
        output.write(requestBytes.getData(), 0, requestBytes.length);
        output.flush();
        var lines = readHead(input).split("\r\n");
        if (!~/^HTTP\/1\.1 101(\s|$)/.match(lines[0])) {
            throw new PreviewFailure(REFUSED);
        }
        var accepted:Null<String> = null;
        for (line in lines) {
            var colon = line.indexOf(":");
            if (colon > 0 && line.substr(0, colon).toLowerCase() == "sec-websocket-accept") {
                accepted = StringTools.trim(line.substr(colon + 1));
            }
        }
        var expectedAccept = Base64.encode(Sha1.make(Bytes.ofString('${key}${WEBSOCKET_GUID}')));
        if (accepted != expectedAccept) {
            throw new PreviewFailure(REFUSED);
        }
    }

    static function readHead(input:DataInputStream):String {
        var head = new BytesBuffer();
        var tail = 0;
        while (head.length < MAX_HEAD_BYTES) {
            var value = input.readUnsignedByte();
            head.addByte(value);
            tail = (tail << 8) | value;
            if (tail == 0x0D0A0D0A) {
                return head.getBytes().toString();
            }
        }
        throw new PreviewFailure(REFUSED);
    }

    static function randomBytes(length:Int):Bytes {
        var bytes = Bytes.alloc(length);
        random.nextBytes(bytes.getData());
        return bytes;
    }

    public function isClosed():Bool {
        guard.acquire();
        var value = closed;
        guard.release();
        return value;
    }

    /** Sends a command and waits for its reply; a protocol error becomes the failure message. */
    public function send(method:String, params:Dynamic, ?sessionId:String):Dynamic {
        var reply = new DevToolsReply();
        guard.acquire();
        if (closed) {
            guard.release();
            throw new PreviewFailure(CLOSED);
        }
        nextId++;
        var id = nextId;
        pending.set(id, reply);
        guard.release();
        var message:Dynamic = {
            id: id,
            method: method,
            params: params
        };
        if (sessionId != null) {
            Reflect.setField(message, "sessionId", sessionId);
        }
        try {
            writeFrame(TEXT, Bytes.ofString(Json.stringify(message)));
        } catch (_:Dynamic) {
            forgetReply(id);
            throw new PreviewFailure(CLOSED);
        }
        if (!reply.lock.wait(COMMAND_SECONDS)) {
            // A browser that stopped answering is replaced on the next capture.
            close();
            throw new PreviewFailure("The preview browser did not respond.");
        }
        if (reply.error != null) {
            throw new PreviewFailure(reply.error);
        }
        return reply.result;
    }

    public function listen(callback:DevToolsCallback):DevToolsListener {
        var listener = new DevToolsListener(callback);
        guard.acquire();
        listeners.push(listener);
        guard.release();
        return listener;
    }

    public function unlisten(listener:DevToolsListener):Void {
        guard.acquire();
        listeners.remove(listener);
        guard.release();
    }

    /** Registers interest in the next `method` event of a session before the command that causes it. */
    public function expect(method:String, sessionId:String):DevToolsEvent {
        var event = new DevToolsEvent(method, sessionId);
        guard.acquire();
        if (closed) {
            event.lock.release();
        } else {
            expected.push(event);
        }
        guard.release();
        return event;
    }

    /** Waits for an expected event; false when it did not arrive in time. */
    public function await(event:DevToolsEvent, seconds:Float):Bool {
        if (!event.lock.wait(seconds)) {
            forget(event);
            return false;
        }
        if (!event.fired) {
            throw new PreviewFailure(CLOSED);
        }
        return true;
    }

    public function forget(event:DevToolsEvent):Void {
        guard.acquire();
        expected.remove(event);
        guard.release();
    }

    public function close():Void {
        try {
            socket.close();
        } catch (_:Dynamic) {}
        closeConnection();
    }

    function forgetReply(id:Int):Void {
        guard.acquire();
        pending.remove(id);
        guard.release();
    }

    function closeConnection():Void {
        guard.acquire();
        if (closed) {
            guard.release();
            return;
        }
        closed = true;
        var replies = [for (reply in pending) reply];
        pending.clear();
        var events = expected;
        expected = [];
        guard.release();
        for (reply in replies) {
            reply.error = CLOSED;
            reply.lock.release();
        }
        for (event in events) {
            event.lock.release();
        }
    }

    /** Reads server frames on a virtual thread until the connection ends. */
    function read():Void {
        var fragments:Null<BytesBuffer> = null;
        var open = true;
        try {
            while (open) {
                var first = input.readUnsignedByte();
                var second = input.readUnsignedByte();
                var finished = (first & 0x80) != 0;
                var opcode = first & 0x0F;
                var length = second & 0x7F;
                if (length == 126) {
                    length = input.readUnsignedShort();
                } else if (length == 127) {
                    var high = input.readInt();
                    var low = input.readInt();
                    if (high != 0 || low < 0) {
                        throw new PreviewFailure(CLOSED);
                    }
                    length = low;
                }
                if (length > MAX_MESSAGE_BYTES) {
                    throw new PreviewFailure(CLOSED);
                }
                var mask:Null<Bytes> = null;
                if ((second & 0x80) != 0) {
                    mask = Bytes.alloc(4);
                    input.readFully(mask.getData(), 0, 4);
                }
                var payload = Bytes.alloc(length);
                if (length > 0) {
                    input.readFully(payload.getData(), 0, length);
                }
                if (mask != null) {
                    for (index in 0...length) {
                        payload.set(index, payload.get(index) ^ mask.get(index & 3));
                    }
                }
                switch (opcode) {
                    case CONTINUATION:
                        if (fragments == null || fragments.length + length > MAX_MESSAGE_BYTES) {
                            open = false;
                        } else {
                            fragments.add(payload);
                            if (finished) {
                                var message = fragments.getBytes();
                                fragments = null;
                                dispatch(message.toString());
                            }
                        }
                    case TEXT | BINARY:
                        if (finished) {
                            dispatch(payload.toString());
                        } else {
                            fragments = new BytesBuffer();
                            fragments.add(payload);
                        }
                    case PING:
                        writeFrame(PONG, payload);
                    case PONG:
                    case CLOSE:
                        try {
                            writeFrame(CLOSE, payload);
                        } catch (_:Dynamic) {}
                        open = false;
                    default:
                        open = false;
                }
            }
        } catch (_:Dynamic) {}
        try {
            socket.close();
        } catch (_:Dynamic) {}
        closeConnection();
    }

    function dispatch(text:String):Void {
        var message:Dynamic = Json.parse(text);
        var id:Dynamic = message.id;
        if (id != null) {
            var key = integerId(id);
            guard.acquire();
            var reply = pending.get(key);
            pending.remove(key);
            guard.release();
            if (reply == null) {
                return;
            }
            var error:Dynamic = message.error;
            if (error != null) {
                var errorMessage:Null<String> = error.message;
                reply.error = errorMessage ?? "The preview browser refused a command.";
            } else {
                reply.result = message.result;
            }
            reply.lock.release();
            return;
        }
        var method:String = message.method;
        var params:Dynamic = message.params;
        var sessionId:Null<String> = message.sessionId;
        guard.acquire();
        var matched = expected.filter(event -> event.method == method
            && event.sessionId == sessionId);
        for (event in matched) {
            expected.remove(event);
        }
        var current = listeners.copy();
        guard.release();
        for (event in matched) {
            event.fired = true;
            event.lock.release();
        }
        for (listener in current) {
            try {
                listener.callback(method, params, sessionId);
            } catch (_:Dynamic) {}
        }
    }

    static function integerId(value:Dynamic):Int {
        if (Std.isOfType(value, Int)) {
            return value;
        }
        return Std.int(value);
    }

    function writeFrame(opcode:Int, payload:Bytes):Void {
        var length = payload.length;
        var headerLength = length < 126 ? 2 : (length < 65536 ? 4 : 10);
        var frame = Bytes.alloc(headerLength + 4 + length);
        frame.set(0, 0x80 | opcode);
        if (length < 126) {
            frame.set(1, 0x80 | length);
        } else if (length < 65536) {
            frame.set(1, 0x80 | 126);
            frame.set(2, (length >> 8) & 0xFF);
            frame.set(3, length & 0xFF);
        } else {
            frame.set(1, 0x80 | 127);
            for (index in 2...6) {
                frame.set(index, 0);
            }
            frame.set(6, (length >>> 24) & 0xFF);
            frame.set(7, (length >> 16) & 0xFF);
            frame.set(8, (length >> 8) & 0xFF);
            frame.set(9, length & 0xFF);
        }
        // Client frames are masked (RFC 6455, section 5.3).
        var mask = randomBytes(4);
        frame.blit(headerLength, mask, 0, 4);
        var offset = headerLength + 4;
        for (index in 0...length) {
            frame.set(offset + index, payload.get(index) ^ mask.get(index & 3));
        }
        writing.acquire();
        try {
            output.write(frame.getData(), 0, frame.length);
            output.flush();
            writing.release();
        } catch (error:Dynamic) {
            writing.release();
            throw error;
        }
    }
}
#end
