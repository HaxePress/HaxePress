package hx.press.backup;

#if jvm
import haxe.Exception;
import haxe.crypto.Base64;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesBuffer;
import haxe.io.BytesOutput;
import haxe.io.Eof;
import haxe.io.Input;
import hx.press.CmsVersion;
import hx.well.storage.StorageDisk;
import hx.well.storage.StorageException;
import java.NativeArray;
import java.StdTypes.Int8;
import java.lang.Exception as JavaException;
import java.security.Key;
import java.security.SecureRandom;
import java.security.spec.AlgorithmParameterSpec;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

// The Haxe 4 JVM extern library predates the JDK's GCM bindings.

@:native("javax.crypto.Cipher")
private extern class BackupAeadCipher {
    public static var ENCRYPT_MODE(default, never):Int;
    public static var DECRYPT_MODE(default, never):Int;
    public static function getInstance(transformation:String):BackupAeadCipher;
    public function init(mode:Int, key:Key, parameters:AlgorithmParameterSpec):Void;
    public function updateAAD(data:NativeArray<Int8>):Void;
    public function doFinal(input:NativeArray<Int8>, offset:Int, length:Int):NativeArray<Int8>;
}

@:native("javax.crypto.spec.GCMParameterSpec")
private extern class BackupGcmParameters implements AlgorithmParameterSpec {
    public function new(tagLength:Int, nonce:NativeArray<Int8>):Void;
}

@:native("javax.crypto.AEADBadTagException")
private extern class BackupAuthenticationError extends JavaException {}

class BackupFormat {
    public static inline var EXTENSION = "hxpress";
    public static inline var FRAME_BYTES = 64 * 1024;
    public static inline var TAG_BYTES = 16;
    static inline var MAGIC = "HXPRESS\x00";
    static inline var MAGIC_BYTES = 8;
    static inline var VERSION = 2;
    static inline var SITE_BACKUP = 1;
    static inline var PREFIX_BYTES = MAGIC_BYTES + 4;
    static inline var MAX_VERSION_BYTES = 64;
    static inline var SALT_BYTES = 32;
    static inline var HMAC = "HmacSHA256";
    static final random = new SecureRandom();
    static final signature = Bytes.ofString(MAGIC);

    public static function maxBytes():Int {
        return PREFIX_BYTES
            + MAX_VERSION_BYTES
            + 4
            + SALT_BYTES
            + encryptedSize(SiteBackupArchive.maxBytes());
    }

    static function encryptedSize(length:Int):Int {
        return length + Math.ceil(length / FRAME_BYTES) * TAG_BYTES;
    }

    public static function seal(disk:StorageDisk, path:String, target:StorageDisk,
            destination:String, encrypted:Bool, appKey:String):Void {
        var length = disk.size(path);
        if (length <= 0 || length > SiteBackupArchive.maxBytes()) {
            throw new Exception("The backup exceeds its upload limit.");
        }
        var version = Bytes.ofString(CmsVersion.version);
        if (version.length == 0 || version.length > MAX_VERSION_BYTES) {
            throw new Exception("The HaxePress version is too long for a backup header.");
        }
        var output = new BytesOutput();
        output.bigEndian = true;
        output.writeString(MAGIC);
        output.writeByte(VERSION);
        output.writeByte(SITE_BACKUP);
        output.writeByte(encrypted ? 1 : 0);
        output.writeByte(version.length);
        output.write(version);
        output.writeInt32(length);
        var key:Null<SecretKeySpec> = null;
        if (encrypted) {
            var salt = Bytes.alloc(SALT_BYTES);
            random.nextBytes(salt.getData());
            output.write(salt);
            key = deriveKey(appKey, salt);
        }
        var header = output.getBytes();
        var source = disk.readStream(path);
        try {
            var payload:Input = encrypted ? new BackupCipherInput(source, header, key, length,
                true) : new BackupInput(source, length);
            target.writeStream(destination, new BackupHeaderInput(header, payload), "private");
        } catch (failure:Dynamic) {
            source.close();
            throw failure;
        }
        source.close();
    }

    /** Read the public header before opening the bounded ZIP payload. */
    public static function open(disk:StorageDisk, path:String, target:StorageDisk,
            destination:String, appKey:String):Bool {
        var size = disk.size(path);
        if (size < PREFIX_BYTES + 5 || size > maxBytes()) {
            throw new Exception("The .hxpress backup has an invalid size.");
        }
        var source = disk.readStream(path);
        var encrypted = false;
        try {
            var prefix = source.read(PREFIX_BYTES);
            var flags = prefix.get(MAGIC_BYTES + 2);
            var versionLength = prefix.get(MAGIC_BYTES + 3);
            if (prefix.sub(0, MAGIC_BYTES).compare(signature) != 0
                || prefix.get(MAGIC_BYTES) != VERSION
                || prefix.get(MAGIC_BYTES + 1) != SITE_BACKUP
                || flags > 1
                || versionLength == 0
                || versionLength > MAX_VERSION_BYTES) {
                throw new Exception("Choose a supported .hxpress site backup.");
            }
            encrypted = flags == 1;
            var version = source.read(versionLength);
            if (version.toString() != CmsVersion.version) {
                throw new Exception('Restore this backup with HaxePress ${version.toString()}. This site runs HaxePress ${CmsVersion.version}.');
            }
            var encodedLength = source.read(4);
            var metadata = new BytesInput(encodedLength);
            metadata.bigEndian = true;
            var length = metadata.readInt32();
            var headerSize = PREFIX_BYTES + versionLength + 4 + (encrypted ? SALT_BYTES : 0);
            var payloadSize = encrypted ? encryptedSize(length) : length;
            if (length <= 0 || length > SiteBackupArchive.maxBytes()
                || size != headerSize + payloadSize) {
                throw new Exception("The .hxpress backup has an invalid size.");
            }
            var stream:Input = new BackupInput(source, length);
            if (encrypted) {
                var salt = source.read(SALT_BYTES);
                var header = new BytesBuffer();
                header.add(prefix);
                header.add(version);
                header.add(encodedLength);
                header.add(salt);
                var key = deriveKey(appKey, salt);
                stream = new BackupCipherInput(source, header.getBytes(), key, length, false);
            }
            target.writeStream(destination, stream, "private");
        } catch (failure:Dynamic) {
            source.close();
            if (failure is StorageException) {
                var storageError:StorageException = failure;
                if (storageError.previous is BackupCipherError) {
                    throw storageError.previous;
                }
            }
            throw failure;
        }
        source.close();
        return encrypted;
    }

    static function deriveKey(appKey:String, salt:Bytes):SecretKeySpec {
        if (!~/^[A-Za-z0-9+\/]{43}=$/.match(appKey)) {
            throw new Exception("A valid original APP_KEY is required for encrypted backups.");
        }
        var master = Base64.decode(appKey);
        if (master.length != 32) {
            throw new Exception("A valid original APP_KEY is required for encrypted backups.");
        }
        // HKDF-SHA256, with one expansion block for a 256-bit key.
        var mac = Mac.getInstance(HMAC);
        mac.init(new SecretKeySpec(salt.getData(), HMAC));
        var extracted = mac.doFinal(master.getData());
        mac.init(new SecretKeySpec(extracted, HMAC));
        var info = Bytes.ofString("HaxePress encrypted backup v2\x01");
        return new SecretKeySpec(mac.doFinal(info.getData()), "AES");
    }
}

private class BackupHeaderInput extends Input {
    final header:BytesInput;
    final source:Input;

    public function new(header:Bytes, source:Input) {
        this.header = new BytesInput(header);
        this.source = source;
    }

    override public function readBytes(bytes:Bytes, offset:Int, length:Int):Int {
        return header.position < header.length ? header.readBytes(bytes, offset,
            length) : source.readBytes(bytes, offset, length);
    }
}

private class BackupCipherError extends Exception {}

private class BackupCipherInput extends Input {
    final source:Input;
    final header:Bytes;
    final key:SecretKeySpec;
    final encrypting:Bool;
    final cipher = BackupAeadCipher.getInstance("AES/GCM/NoPadding");
    final buffer = Bytes.alloc(BackupFormat.FRAME_BYTES + BackupFormat.TAG_BYTES);
    final nonce = Bytes.alloc(12);
    var pending:Bytes;
    var offset = 0;
    var index = 0;
    var remaining:Int;

    public function new(source:Input, header:Bytes, key:SecretKeySpec, length:Int,
            encrypting:Bool) {
        this.source = source;
        this.header = header;
        this.key = key;
        this.encrypting = encrypting;
        remaining = length;
        pending = Bytes.alloc(0);
    }

    function refill():Void {
        if (remaining == 0) {
            try {
                source.readByte();
                throw new BackupCipherError("The encrypted backup contains unexpected data.");
            } catch (_:Eof) {}
            throw new Eof();
        }

        var count = Std.int(Math.min(remaining, BackupFormat.FRAME_BYTES));
        var inputLength = encrypting ? count : count + BackupFormat.TAG_BYTES;
        try {
            source.readFullBytes(buffer, 0, inputLength);
        } catch (_:Eof) {
            throw new BackupCipherError("The encrypted backup is incomplete.");
        }

        // The random salt gives each file its own key. The frame index is unique under that key.
        for (byte in 0...4) {
            nonce.set(8 + byte, (index >>> (24 - byte * 8)) & 255);
        }
        var mode = encrypting ? BackupAeadCipher.ENCRYPT_MODE : BackupAeadCipher.DECRYPT_MODE;
        cipher.init(mode, key,
            new BackupGcmParameters(BackupFormat.TAG_BYTES * 8, nonce.getData()));
        var authenticatedHeader:NativeArray<Int8> = header.getData();
        cipher.updateAAD(authenticatedHeader);
        try {
            pending = Bytes.ofData(cipher.doFinal(buffer.getData(), 0, inputLength));
        } catch (_:BackupAuthenticationError) {
            throw new BackupCipherError("The encrypted backup could not be opened. Use the original APP_KEY and an intact file.");
        }
        remaining -= count;
        index++;
        offset = 0;
    }

    public override function readBytes(bytes:Bytes, position:Int, length:Int):Int {
        if (length == 0) {
            return 0;
        }
        if (offset == pending.length) {
            refill();
        }
        var count = Std.int(Math.min(length, pending.length - offset));
        bytes.blit(position, pending, offset, count);
        offset += count;
        return count;
    }
}
#end
