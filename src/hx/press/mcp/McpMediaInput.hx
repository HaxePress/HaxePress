package hx.press.mcp;

import haxe.Exception;
import haxe.crypto.Base64;
import haxe.io.Bytes;
import hx.press.mcp.McpSchema.field;
import hx.press.mcp.McpSchema.optional;
#if jvm
import haxe.io.BytesBuffer;
import java.net.HttpURLConnection;
import java.net.URL;
#elseif php
import php.Syntax;
#end

typedef McpImage = {
    var bytes:Bytes;
    var name:Null<String>;
}

/**
    Image input for the upload tools: canonical Base64 bytes, or an
    attachment that a host such as ChatGPT supplies through the
    `openai/fileParams` input metadata. Attachments are read from the
    ChatGPT content domain only, with a size and time limit.
**/
class McpMediaInput {
    public static inline var MAX_IMAGE_BYTES = 5 * 1048576;
    static inline var TIMEOUT_MS = 10000;

    public static final fileParams:Dynamic = {"openai/fileParams": ["file"]};

    /** Base64 text for an image up to the limit. **/
    public static function encoded():Dynamic {
        return McpSchema.string(Math.ceil(MAX_IMAGE_BYTES / 3) * 4, 4);
    }

    /** A host-supplied attachment. **/
    public static function attachment():Dynamic {
        return McpSchema.object([
            field("download_url", McpSchema.string(4096)),
            field("file_id", McpSchema.string(256, 1)),
            optional("mime_type", McpSchema.string(128)),
            optional("file_name", McpSchema.string(180))
        ]);
    }

    public static function image(base64:Null<String>, file:Null<Dynamic>,
            name:Null<String>):McpImage {
        if (file == null) {
            if (base64 == null || !~/^[A-Za-z0-9+\/]+={0,2}$/.match(base64)) {
                throw new Exception("Supply an attached image or canonical Base64 image data.");
            }
            var bytes:Bytes;
            try {
                bytes = Base64.decode(base64);
            } catch (_:Dynamic) {
                throw new Exception("Supply an image under 5 MB as canonical Base64.");
            }
            if (bytes.length == 0 || bytes.length > MAX_IMAGE_BYTES
                || Base64.encode(bytes) != base64) {
                throw new Exception("Supply an image under 5 MB as canonical Base64.");
            }
            return {bytes: bytes, name: name};
        }
        if (base64 != null) {
            throw new Exception("Choose one source for the image.");
        }
        var address:String = file.download_url;
        var parts = ~/^https:\/\/([A-Za-z0-9.-]+)(\/[^#\s]*)?$/;
        if (!parts.match(address)
            || !StringTools.endsWith(parts.matched(1).toLowerCase(), ".oaiusercontent.com")) {
            throw new Exception("Choose a ChatGPT attachment or supply canonical Base64 image data.");
        }
        var bytes = download(address);
        if (bytes.length == 0) {
            throw new Exception("The image attachment was empty.");
        }
        var fileName:Null<String> = file.file_name;
        return {bytes: bytes, name: name ?? fileName};
    }

    static function download(address:String):Bytes {
        var unavailable = "Choose an available image attachment under 5 MB.";
        #if jvm
        var connection:HttpURLConnection = cast new URL(address).openConnection();
        connection.setConnectTimeout(TIMEOUT_MS);
        connection.setReadTimeout(TIMEOUT_MS);
        connection.setInstanceFollowRedirects(false);
        try {
            var status = connection.getResponseCode();
            var length = connection.getContentLengthLong();
            if (status < 200 || status >= 300 || length > MAX_IMAGE_BYTES) {
                connection.disconnect();
                throw new Exception(unavailable);
            }
            var input = connection.getInputStream();
            var buffer = Bytes.alloc(65536);
            var result = new BytesBuffer();
            var size = input.read(buffer.getData(), 0, buffer.length);
            while (size != -1) {
                if (result.length + size > MAX_IMAGE_BYTES) {
                    input.close();
                    connection.disconnect();
                    throw new Exception("The CMS response exceeds its size limit.");
                }
                result.addBytes(buffer, 0, size);
                size = input.read(buffer.getData(), 0, buffer.length);
            }
            input.close();
            connection.disconnect();
            return result.getBytes();
        } catch (error:Exception) {
            connection.disconnect();
            throw error;
        } catch (_:Dynamic) {
            connection.disconnect();
            throw new Exception(unavailable);
        }
        #elseif php
        var options = Syntax.code("['http' => ['method' => 'GET', 'timeout' => {0}, 'follow_location' => 0, 'ignore_errors' => true]]",
            TIMEOUT_MS / 1000);
        var context = Syntax.code("stream_context_create({0})", options);
        var body:Dynamic = Syntax.code("@file_get_contents({0}, false, {1}, 0, {2})", address,
            context, MAX_IMAGE_BYTES + 1);
        var status:Int = Syntax.code("(isset($http_response_header[0]) && preg_match('#^HTTP/\\S+\\s+(\\d\\d\\d)#', $http_response_header[0], $m)) ? (int) $m[1] : 0");
        if (body == false || status < 200 || status >= 300) {
            throw new Exception(unavailable);
        }
        var bytes = Bytes.ofString(body);
        if (bytes.length > MAX_IMAGE_BYTES) {
            throw new Exception(unavailable);
        }
        return bytes;
        #else
        throw new Exception(unavailable);
        #end
    }
}
