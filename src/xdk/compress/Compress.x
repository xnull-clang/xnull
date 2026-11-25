// xdk.compress —— L4 gzip/zlib/deflate 核心（M18.2）
//
// 本文件实现 4/14 类型：CompressionLevel、Gzip、Zlib、Deflate。
// Zstd/Lz4/Brotli/Zip/Tar 仍为 planned。
// 稳定性：preview。合同见 docs/design/utils/compress/。
package xdk.compress
import xdk.errors
import xdk.bytes
import xdk.text
import xdk.crypto

// ---------- CompressionLevel ----------
enum CompressionLevel {
    None,
    Fastest,
    Fast,
    Default,
    Maximum,
}

Int compressionLevelValue(CompressionLevel level) {
    if level == CompressionLevel.None { return 0 }
    if level == CompressionLevel.Fastest { return 1 }
    if level == CompressionLevel.Fast { return 3 }
    if level == CompressionLevel.Maximum { return 9 }
    return 6
}

// ---------- 内部 ----------
static Int compressDefaultLimit() {
    return 67108864
}

static String toHexFast(Bytes data) {
    String digits = "0123456789abcdef"
    List<String> parts = []
    Int index = 0
    while index < data.length() {
        Int value = data.get(index)
        parts.push(digits.substring(value / 16, 1) + digits.substring(value % 16, 1))
        index = index + 1
    }
    return parts.join("")
}

static Error decompressError(Int code) {
    if code == 1 {
        return new BasicError(ErrorKind.InvalidArgument, "decompression limit exceeded or empty input")
    }
    return new BasicError(ErrorKind.DataCorrupted, "decompression failed")
}

// ---------- Gzip ----------
class Gzip {
    private Gzip() { }

    static Result<Bytes, Error> compress(Bytes data, CompressionLevel level) {
        if data == null { throw "Gzip.compress: null data" }
        String hex = gzipCompressLevelHexRaw(toHexFast(data), compressionLevelValue(level))
        if compressLastErrorRaw() != 0 {
            return Err(new BasicError(ErrorKind.DataCorrupted, "gzip compression failed"))
        }
        return Ok(fromHex(hex))
    }

    static Result<Bytes, Error> decompress(Bytes data) {
        return Gzip.decompressWithLimit(data, compressDefaultLimit())
    }

    static Result<Bytes, Error> decompressWithLimit(Bytes data, Int maxBytes) {
        if data == null { throw "Gzip.decompressWithLimit: null data" }
        String hex = gzipDecompressLimitedHexRaw(toHexFast(data), maxBytes)
        Int code = compressLastErrorRaw()
        if code != 0 { return Err(decompressError(code)) }
        return Ok(fromHex(hex))
    }

    static Bool isGzip(Bytes data) {
        if data == null { return false }
        if data.length() < 2 { return false }
        return data.get(0) == 0x1f && data.get(1) == 0x8b
    }
}

// ---------- Zlib ----------
class Zlib {
    private Zlib() { }

    static Result<Bytes, Error> compress(Bytes data, CompressionLevel level) {
        if data == null { throw "Zlib.compress: null data" }
        String hex = zlibCompressLevelHexRaw(toHexFast(data), compressionLevelValue(level))
        if compressLastErrorRaw() != 0 {
            return Err(new BasicError(ErrorKind.DataCorrupted, "zlib compression failed"))
        }
        return Ok(fromHex(hex))
    }

    static Result<Bytes, Error> decompress(Bytes data) {
        return Zlib.decompressWithLimit(data, compressDefaultLimit())
    }

    static Result<Bytes, Error> decompressWithLimit(Bytes data, Int maxBytes) {
        if data == null { throw "Zlib.decompressWithLimit: null data" }
        String hex = zlibDecompressLimitedHexRaw(toHexFast(data), maxBytes)
        Int code = compressLastErrorRaw()
        if code != 0 { return Err(decompressError(code)) }
        return Ok(fromHex(hex))
    }

    static Bool isZlib(Bytes data) {
        if data == null { return false }
        if data.length() < 2 { return false }
        return data.get(0) == 0x78
    }
}

// ---------- Deflate ----------
class Deflate {
    private Deflate() { }

    static Result<Bytes, Error> compress(Bytes data, CompressionLevel level) {
        if data == null { throw "Deflate.compress: null data" }
        String hex = deflateCompressLevelHexRaw(toHexFast(data), compressionLevelValue(level))
        if compressLastErrorRaw() != 0 {
            return Err(new BasicError(ErrorKind.DataCorrupted, "deflate compression failed"))
        }
        return Ok(fromHex(hex))
    }

    static Result<Bytes, Error> decompress(Bytes data) {
        return Deflate.decompressWithLimit(data, compressDefaultLimit())
    }

    static Result<Bytes, Error> decompressWithLimit(Bytes data, Int maxBytes) {
        if data == null { throw "Deflate.decompressWithLimit: null data" }
        String hex = deflateDecompressLimitedHexRaw(toHexFast(data), maxBytes)
        Int code = compressLastErrorRaw()
        if code != 0 { return Err(decompressError(code)) }
        return Ok(fromHex(hex))
    }
}


// ---------- TarEntry ----------
class TarEntry {
    final String _name
    final Bytes _content
    final Int _mode
    final Long _modifiedSeconds
    final Bool _directory

    TarEntry(String name, Bytes content, Int mode, Long modifiedSeconds, Bool directory) {
        if name == null || name.length() == 0 { throw "TarEntry: empty name" }
        if content == null { throw "TarEntry: null content" }
        if mode < 0 || mode > 4095 { throw "TarEntry: mode out of range" }
        if modifiedSeconds < 0 { throw "TarEntry: negative time" }
        if name.substring(0, 1) == "/" { throw "TarEntry: absolute name" }
        if name.indexOf("\\") >= 0 { throw "TarEntry: invalid name" }
        Int index = 0
        while index < name.length() {
            if name.get(index) < 32 { throw "TarEntry: invalid name" }
            index = index + 1
        }
        List<String> parts = name.split("/")
        index = 0
        while index < parts.length() {
            if parts.get(index) == ".." { throw "TarEntry: parent segment" }
            index = index + 1
        }
        Bool endsSlash = name.substring(name.length() - 1, 1) == "/"
        if directory && !endsSlash { throw "TarEntry: directory name must end with slash" }
        if !directory && endsSlash { throw "TarEntry: file name must not end with slash" }
        if directory && content.length() > 0 { throw "TarEntry: directory content must be empty" }
        self._name = name
        self._content = copy(content)
        self._mode = mode
        self._modifiedSeconds = modifiedSeconds
        self._directory = directory
    }

    static TarEntry file(String name, Bytes content, Int mode, Long modifiedSeconds) {
        return new TarEntry(name, content, mode, modifiedSeconds, false)
    }

    static TarEntry directory(String name, Int mode, Long modifiedSeconds) {
        if name == null || name.length() == 0 { throw "TarEntry.directory: empty name" }
        String normalized = name
        if normalized.substring(normalized.length() - 1, 1) != "/" {
            normalized = normalized + "/"
        }
        return new TarEntry(normalized, Bytes.fromString(""), mode, modifiedSeconds, true)
    }

    String name() { return self._name }
    Bytes content() { return copy(self._content) }
    Long size() { return self._content.length() as Long }
    Int mode() { return self._mode }
    Long modifiedSeconds() { return self._modifiedSeconds }
    Bool isDirectory() { return self._directory }

    String describe() {
        return self._name + "(size=" + str(self._content.length()) + ",mode=" +
            str(self._mode) + ",dir=" + str(self._directory) + ")"
    }
}

// ---------- Tar helpers ----------
static String tarOctal(Long value, Int digits) {
    String digitsText = "01234567"
    String out = ""
    Long current = value
    Int index = 0
    while index < digits {
        Long digit = current % (8 as Long)
        out = digitsText.substring(digit as Int, 1) + out
        current = current / (8 as Long)
        index = index + 1
    }
    return out
}

static Void tarPut(Bytes block, Int offset, String text, Int max) {
    Int index = 0
    while index < text.length() && index < max {
        block.set(offset + index, text.get(index))
        index = index + 1
    }
}

static Void tarPutOctal(Bytes block, Int offset, Long value, Int digits) {
    tarPut(block, offset, tarOctal(value, digits - 1), digits - 1)
    block.set(offset + digits - 1, 0)
}

static Void tarPutChecksum(Bytes block, Int offset, Long value) {
    String text = tarOctal(value, 6)
    tarPut(block, offset, text, 6)
    block.set(offset + 6, 0)
    block.set(offset + 7, 32)
}

static Long tarParseOctal(Bytes data, Int offset, Int length) {
    Long value = 0 as Long
    Bool found = false
    Int index = 0
    while index < length {
        Int code = data.get(offset + index)
        if code == 0 || code == 32 { index = index + 1; continue }
        if code < 48 || code > 55 { return -1 as Long }
        value = value * (8 as Long) + ((code - 48) as Long)
        found = true
        index = index + 1
    }
    if !found { return 0 as Long }
    return value
}

static String tarReadText(Bytes data, Int offset, Int max) {
    Int end = offset
    while end < offset + max {
        if data.get(end) == 0 { break }
        end = end + 1
    }
    return data.slice(offset, end).toString()
}

static Bool tarBlockZero(Bytes data, Int offset) {
    Int index = 0
    while index < 512 {
        if data.get(offset + index) != 0 { return false }
        index = index + 1
    }
    return true
}

static Long tarChecksum(Bytes data, Int offset) {
    Long sum = 0 as Long
    Int index = 0
    while index < 512 {
        if index >= 148 && index < 156 { sum = sum + (32 as Long) }
        else { sum = sum + (data.get(offset + index) as Long) }
        index = index + 1
    }
    return sum
}

static Bool tarNameSafe(String name, Bool directory) {
    if name == null || name.length() == 0 { return false }
    if name.substring(0, 1) == "/" { return false }
    if name.indexOf("\\") >= 0 { return false }
    Int index = 0
    while index < name.length() {
        if name.get(index) < 32 { return false }
        index = index + 1
    }
    List<String> parts = name.split("/")
    index = 0
    while index < parts.length() {
        if parts.get(index) == ".." { return false }
        index = index + 1
    }
    Bool endsSlash = name.substring(name.length() - 1, 1) == "/"
    if directory { return endsSlash }
    return !endsSlash
}

static Void tarMkdirAll(String path) {
    if path.length() == 0 { return }
    Int index = 0
    while index < path.length() {
        if index == path.length() - 1 || path.substring(index + 1, 1) == "/" {
            String prefix = path.substring(0, index + 1)
            if prefix != "/" { dirMakeRaw(prefix) }
        }
        index = index + 1
    }
}

static String tarParent(String path) {
    Int slash = -1
    Int probe = 0
    while probe < path.length() {
        if path.substring(probe, 1) == "/" { slash = probe }
        probe = probe + 1
    }
    if slash < 0 { return "" }
    if slash == 0 { return "/" }
    return path.substring(0, slash)
}

// ---------- Tar ----------
class Tar {
    private Tar() { }

    static Result<Bytes, Error> write(List<TarEntry> entries) {
        if entries == null { throw "Tar.write: null entries" }
        Int index = 0
        Long dataOffset = 0 as Long
        while index < entries.length() {
            TarEntry entry = entries.get(index)
            Long blocks = (entry.size() + 511 as Long) / 512 as Long
            dataOffset = dataOffset + 512 as Long + blocks * 512 as Long
            index = index + 1
        }
        Long total = dataOffset + 1024 as Long
        Bytes output = Bytes.alloc(total as Int)
        Int offset = 0
        index = 0
        while index < entries.length() {
            TarEntry entry = entries.get(index)
            String fullName = entry.name()
            String name = fullName
            String prefix = ""
            if fullName.length() > 100 {
                Int split = -1
                Int start = fullName.length() - 100
                if start < 1 { start = 1 }
                Int probe = start
                while probe < fullName.length() {
                    if fullName.substring(probe, 1) == "/" && probe <= 155 &&
                       fullName.length() - probe - 1 <= 100 {
                        split = probe
                        break
                    }
                    probe = probe + 1
                }
                if split < 0 {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "Tar: name too long"))
                }
                prefix = fullName.substring(0, split)
                name = fullName.substring(split + 1, fullName.length() - split - 1)
            }
            Bytes header = Bytes.alloc(512)
            tarPut(header, 0, name, 100)
            tarPutOctal(header, 100, entry.mode() as Long, 8)
            tarPutOctal(header, 108, 0 as Long, 8)
            tarPutOctal(header, 116, 0 as Long, 8)
            tarPutOctal(header, 124, entry.size(), 12)
            tarPutOctal(header, 136, entry.modifiedSeconds(), 12)
            Int fill = 0
            while fill < 8 { header.set(148 + fill, 32); fill = fill + 1 }
            if entry.isDirectory() { header.set(156, 53) } else { header.set(156, 48) }
            tarPut(header, 257, "ustar", 5)
            header.set(262, 0)
            tarPut(header, 263, "00", 2)
            tarPut(header, 345, prefix, 155)
            Long checksum = tarChecksum(header, 0)
            tarPutChecksum(header, 148, checksum)
            Int copyIndex = 0
            while copyIndex < 512 {
                output.set(offset + copyIndex, header.get(copyIndex))
                copyIndex = copyIndex + 1
            }
            offset = offset + 512
            Bytes content = entry.content()
            copyIndex = 0
            while copyIndex < content.length() {
                output.set(offset + copyIndex, content.get(copyIndex))
                copyIndex = copyIndex + 1
            }
            Long padded = ((entry.size() + 511 as Long) / 512 as Long) * 512 as Long
            offset = offset + (padded as Int)
            index = index + 1
        }
        return Ok(output)
    }

    static Result<Unit, Error> writeTo(String path, List<TarEntry> entries) {
        if path == null { throw "Tar.writeTo: null path" }
        Result<Bytes, Error> data = Tar.write(entries)
        if data.isErr() { return Err(data.error()) }
        String parent = tarParent(path)
        if parent.length() > 0 { tarMkdirAll(parent) }
        Int rc = writeFileHexRaw(path, toHexFast(data.value()), false)
        if rc != 0 {
            return Err(new BasicError(ErrorKind.Io, "Tar.writeTo: write failed"))
        }
        return Ok()
    }

    static Result<List<TarEntry>, Error> read(Bytes data) {
        return Tar.readWithLimits(data, 10000, 268435456)
    }

    static Result<List<TarEntry>, Error> readWithLimits(Bytes data, Int maxEntries, Int maxTotalBytes) {
        if data == null { throw "Tar.readWithLimits: null data" }
        if maxEntries <= 0 || maxTotalBytes <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Tar: invalid limit"))
        }
        List<TarEntry> entries = []
        if data.length() == 0 { return Ok(entries) }
        if data.length() % 512 != 0 {
            return Err(new BasicError(ErrorKind.DataCorrupted, "Tar: truncated data"))
        }
        Int offset = 0
        Long total = 0 as Long
        Bool ended = false
        while offset + 512 <= data.length() {
            if tarBlockZero(data, offset) {
                ended = true
                break
            }
            String name = tarReadText(data, offset, 100)
            String prefix = tarReadText(data, offset + 345, 155)
            String magic = tarReadText(data, offset + 257, 6)
            if magic != "ustar" && magic != "ustar " {
                return Err(new BasicError(ErrorKind.DataCorrupted, "Tar: invalid magic"))
            }
            Long stored = tarParseOctal(data, offset + 148, 8)
            Long computed = tarChecksum(data, offset)
            if stored < 0 || stored != computed {
                return Err(new BasicError(ErrorKind.DataCorrupted, "Tar: checksum mismatch"))
            }
            Int type = data.get(offset + 156)
            Bool directory = false
            if type == 48 || type == 0 {
                directory = false
            } else if type == 53 {
                directory = true
            } else {
                return Err(new BasicError(ErrorKind.Unsupported, "Tar: unsupported entry type"))
            }
            Long size = tarParseOctal(data, offset + 124, 12)
            Long modeValue = tarParseOctal(data, offset + 100, 8)
            Long time = tarParseOctal(data, offset + 136, 12)
            if size < 0 || modeValue < 0 || time < 0 {
                return Err(new BasicError(ErrorKind.DataCorrupted, "Tar: invalid numeric field"))
            }
            String fullName = name
            if prefix.length() > 0 { fullName = prefix + "/" + name }
            if !tarNameSafe(fullName, directory) {
                return Err(new BasicError(ErrorKind.DataCorrupted, "Tar: unsafe entry name"))
            }
            if directory && size != 0 {
                return Err(new BasicError(ErrorKind.DataCorrupted, "Tar: directory with content"))
            }
            Long contentStart = offset as Long + 512 as Long
            if contentStart + size > data.length() as Long {
                return Err(new BasicError(ErrorKind.DataCorrupted, "Tar: truncated content"))
            }
            if entries.length() + 1 > maxEntries {
                return Err(new BasicError(ErrorKind.InvalidArgument, "Tar: maxEntries exceeded"))
            }
            total = total + size
            if total > maxTotalBytes as Long {
                return Err(new BasicError(ErrorKind.InvalidArgument, "Tar: maxTotalBytes exceeded"))
            }
            Bytes content = data.slice(contentStart as Int, (contentStart + size) as Int)
            entries.push(new TarEntry(fullName, content, modeValue as Int, time, directory))
            Long padded = ((size + 511 as Long) / 512 as Long) * 512 as Long
            offset = (contentStart + padded) as Int
        }
        if offset < data.length() && !tarBlockZero(data, offset) {
            return Err(new BasicError(ErrorKind.DataCorrupted, "Tar: missing end marker"))
        }
        if !ended && offset + 512 > data.length() && data.length() > 0 {
            return Err(new BasicError(ErrorKind.DataCorrupted, "Tar: missing end marker"))
        }
        return Ok(entries)
    }

    static Result<List<TarEntry>, Error> readFrom(String path) {
        if path == null { throw "Tar.readFrom: null path" }
        if fileExistsRaw(path) == 0 {
            return Err(new BasicError(ErrorKind.NotFound, "Tar.readFrom: file not found"))
        }
        String hex = readFileHexRaw(path)
        Int size = fileSizeRaw(path)
        if size > 0 && hex.length() != size * 2 {
            return Err(new BasicError(ErrorKind.Io, "Tar.readFrom: read failed"))
        }
        return Tar.read(fromHex(hex))
    }

    static Result<Unit, Error> extractTo(String directory, List<TarEntry> entries) {
        if directory == null || entries == null { throw "Tar.extractTo: null argument" }
        tarMkdirAll(directory)
        String base = directory
        if base.substring(base.length() - 1, 1) == "/" {
            base = base.substring(0, base.length() - 1)
        }
        Int index = 0
        while index < entries.length() {
            TarEntry entry = entries.get(index)
            String target = base + "/" + entry.name()
            if entry.isDirectory() {
                tarMkdirAll(target)
            } else {
                String parent = tarParent(target)
                if parent.length() > 0 { tarMkdirAll(parent) }
                Int rc = writeFileHexRaw(target, toHexFast(entry.content()), false)
                if rc != 0 {
                    return Err(new BasicError(ErrorKind.Io, "Tar.extractTo: write failed"))
                }
                if entry.mode() != 0 {
                    pathChmodRaw(target, entry.mode() as Int)
                }
            }
            index = index + 1
        }
        return Ok()
    }

    static Bool isTar(Bytes data) {
        if data == null { throw "Tar.isTar: null data" }
        if data.length() < 512 { return false }
        if data.length() >= 263 {
            String magic = tarReadText(data, 257, 6)
            if magic == "ustar" { return true }
        }
        Long stored = tarParseOctal(data, 148, 8)
        Long computed = tarChecksum(data, 0)
        return stored >= 0 && stored == computed && stored > 0
    }
}

// ---------- ZipEntry ----------
class ZipEntry {
    final String _name
    final Long _size
    final Long _compressedSize
    final Long _crc32
    final Long _modifiedMillis
    final Bool _directory
    final String? _comment

    ZipEntry(String name, Long size, Long compressedSize, Long crc32,
             Long modifiedMillis, Bool directory, String? comment) {
        if name == null || name.length() == 0 { throw "ZipEntry: empty name" }
        if !zipNameSafe(name, directory) { throw "ZipEntry: invalid name" }
        if size < 0 || compressedSize < 0 || modifiedMillis < 0 {
            throw "ZipEntry: negative size/time"
        }
        if crc32 < 0 || crc32 > 4294967295 as Long { throw "ZipEntry: crc32 out of range" }
        if directory && size != 0 { throw "ZipEntry: directory size must be zero" }
        if comment != null {
            String commentText = comment as String
            if commentText.length() > 65535 { throw "ZipEntry: comment too long" }
        }
        self._name = name
        self._size = size
        self._compressedSize = compressedSize
        self._crc32 = crc32
        self._modifiedMillis = modifiedMillis
        self._directory = directory
        self._comment = comment
    }

    String name() { return self._name }
    Long size() { return self._size }
    Long compressedSize() { return self._compressedSize }
    Long crc32() { return self._crc32 }
    Long modifiedMillis() { return self._modifiedMillis }
    Bool isDirectory() { return self._directory }
    String? comment() { return self._comment }

    String describe() {
        return self._name + "(size=" + str(self._size) + ",packed=" +
            str(self._compressedSize) + ",dir=" + str(self._directory) + ")"
    }
}

// ---------- ZipOptions ----------
class ZipOptions {
    CompressionLevel _compressionLevel
    Int _maxEntryBytes
    Int _maxTotalBytes
    Bool _verifyCrc
    String? _comment

    ZipOptions() {
        self._compressionLevel = CompressionLevel.Default
        self._maxEntryBytes = 16777216
        self._maxTotalBytes = 67108864
        self._verifyCrc = true
        self._comment = null
    }

    ZipOptions compressionLevel(CompressionLevel value) {
        self._compressionLevel = value
        return self
    }

    ZipOptions maxEntryBytes(Int value) {
        if value <= 0 { throw "ZipOptions.maxEntryBytes: must be positive" }
        if value > self._maxTotalBytes { throw "ZipOptions.maxEntryBytes: exceeds maxTotalBytes" }
        self._maxEntryBytes = value
        return self
    }

    ZipOptions maxTotalBytes(Int value) {
        if value <= 0 { throw "ZipOptions.maxTotalBytes: must be positive" }
        if value < self._maxEntryBytes { throw "ZipOptions.maxTotalBytes: below maxEntryBytes" }
        self._maxTotalBytes = value
        return self
    }

    ZipOptions verifyCrc(Bool value) {
        self._verifyCrc = value
        return self
    }

    ZipOptions comment(String? value) {
        if value != null {
            String text = value as String
            if text.length() > 65535 { throw "ZipOptions.comment: too long" }
        }
        self._comment = value
        return self
    }

    CompressionLevel getCompressionLevel() { return self._compressionLevel }
    Int getMaxEntryBytes() { return self._maxEntryBytes }
    Int getMaxTotalBytes() { return self._maxTotalBytes }
    Bool isVerifyCrc() { return self._verifyCrc }
    String? getComment() { return self._comment }

    ZipOptions copy() {
        ZipOptions out = new ZipOptions()
        out._compressionLevel = self._compressionLevel
        out._maxEntryBytes = self._maxEntryBytes
        out._maxTotalBytes = self._maxTotalBytes
        out._verifyCrc = self._verifyCrc
        out._comment = self._comment
        return out
    }
}

// ---------- ZIP 内部 ----------
static Bool zipNameSafe(String name, Bool directory) {
    if name == null || name.length() == 0 { return false }
    if name.substring(0, 1) == "/" { return false }
    if name.indexOf("\\\\") >= 0 { return false }
    Int index = 0
    while index < name.length() {
        if name.get(index) < 32 { return false }
        index = index + 1
    }
    List<String> parts = name.split("/")
    index = 0
    while index < parts.length() {
        if parts.get(index) == ".." { return false }
        index = index + 1
    }
    Bool endsSlash = name.substring(name.length() - 1, 1) == "/"
    if directory { return endsSlash }
    return !endsSlash
}

static Void zipPush16(Bytes out, Long value) {
    out.push((value & 255 as Long) as Int)
    out.push(((value >> 8) & 255 as Long) as Int)
}

static Void zipPush32(Bytes out, Long value) {
    out.push((value & 255 as Long) as Int)
    out.push(((value >> 8) & 255 as Long) as Int)
    out.push(((value >> 16) & 255 as Long) as Int)
    out.push(((value >> 24) & 255 as Long) as Int)
}

static Void zipPushText(Bytes out, String text) {
    Int index = 0
    while index < text.length() {
        out.push(text.get(index))
        index = index + 1
    }
}

static Long zipRead16(Bytes data, Int offset) {
    return (data.get(offset) as Long) + ((data.get(offset + 1) as Long) << 8)
}

static Long zipRead32(Bytes data, Int offset) {
    return (data.get(offset) as Long) +
        ((data.get(offset + 1) as Long) << 8) +
        ((data.get(offset + 2) as Long) << 16) +
        ((data.get(offset + 3) as Long) << 24)
}

class ZipPending {
    final String name
    final Bytes content
    final Bool directory
    ZipPending(String entryName, Bytes entryContent, Bool isDirectory) {
        self.name = entryName
        self.content = entryContent
        self.directory = isDirectory
    }
}

class ZipCentral {
    final ZipEntry entry
    final Int method
    final Long offset
    ZipCentral(ZipEntry storedEntry, Int storedMethod, Long headerOffset) {
        self.entry = storedEntry
        self.method = storedMethod
        self.offset = headerOffset
    }
}

class ZipArchiveItem {
    final ZipEntry entry
    final Int method
    final Long dataOffset
    ZipArchiveItem(ZipEntry archiveEntry, Int storedMethod, Long offset) {
        self.entry = archiveEntry
        self.method = storedMethod
        self.dataOffset = offset
    }
}

// ---------- ZipWriter ----------
class ZipWriter {
    final ZipOptions _options
    List<ZipPending> _pending
    Bool _finished
    Bool _closed
    Bytes? _result
    Long _total

    ZipWriter(ZipOptions options) {
        if options == null { throw "ZipWriter: null options" }
        self._options = options.copy()
        self._pending = []
        self._finished = false
        self._closed = false
        self._result = null
        self._total = 0 as Long
    }

    Result<Unit, Error> addFile(String name, Bytes content) {
        if name == null || content == null { throw "ZipWriter.addFile: null argument" }
        if self._finished || self._closed {
            return Err(new BasicError(ErrorKind.Unavailable, "ZipWriter.addFile: writer is closed"))
        }
        if !zipNameSafe(name, false) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "ZipWriter.addFile: invalid name"))
        }
        if name.length() > 65535 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "ZipWriter.addFile: name too long"))
        }
        Int index = 0
        while index < self._pending.length() {
            if self._pending.get(index).name == name {
                return Err(new BasicError(ErrorKind.AlreadyExists, "ZipWriter.addFile: duplicate name"))
            }
            index = index + 1
        }
        Long size = content.length() as Long
        if size > self._options.getMaxEntryBytes() as Long {
            return Err(new BasicError(ErrorKind.InvalidArgument, "ZipWriter.addFile: entry too large"))
        }
        if self._total + size > self._options.getMaxTotalBytes() as Long {
            return Err(new BasicError(ErrorKind.InvalidArgument, "ZipWriter.addFile: total too large"))
        }
        self._total = self._total + size
        self._pending.push(new ZipPending(name, copy(content), false))
        return Ok()
    }

    Result<Unit, Error> addDirectory(String name) {
        if name == null { throw "ZipWriter.addDirectory: null name" }
        if self._finished || self._closed {
            return Err(new BasicError(ErrorKind.Unavailable, "ZipWriter.addDirectory: writer is closed"))
        }
        String normalized = name
        if normalized.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "ZipWriter.addDirectory: empty name"))
        }
        if normalized.substring(normalized.length() - 1, 1) != "/" {
            normalized = normalized + "/"
        }
        if !zipNameSafe(normalized, true) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "ZipWriter.addDirectory: invalid name"))
        }
        Int index = 0
        while index < self._pending.length() {
            if self._pending.get(index).name == normalized {
                return Err(new BasicError(ErrorKind.AlreadyExists, "ZipWriter.addDirectory: duplicate name"))
            }
            index = index + 1
        }
        self._pending.push(new ZipPending(normalized, Bytes.fromString(""), true))
        return Ok()
    }

    Result<Bytes, Error> finish() {
        if self._finished {
            return Ok(copy(self._result as Bytes))
        }
        if self._closed {
            return Err(new BasicError(ErrorKind.Unavailable, "ZipWriter.finish: writer is closed"))
        }
        Bytes out = Bytes.fromString("")
        List<ZipCentral> central = []
        Int index = 0
        while index < self._pending.length() {
            ZipPending pending = self._pending.get(index)
            Bytes packed = pending.content
            Int method = 0
            if !pending.directory && self._options.getCompressionLevel() != CompressionLevel.None {
                Result<Bytes, Error> compressed = Deflate.compress(pending.content, self._options.getCompressionLevel())
                if compressed.isErr() { return Err(compressed.error()) }
                packed = compressed.value()
                method = 8
            }
            Long crc = 0 as Long
            if !pending.directory {
                crc = Checksum.compute(ChecksumAlgorithm.Crc32, pending.content)
            }
            if packed.length() as Long > 4294967295 as Long || pending.content.length() as Long > 4294967295 as Long {
                return Err(new BasicError(ErrorKind.InvalidArgument, "ZipWriter: zip64 required"))
            }
            Long offset = out.length() as Long
            zipPush32(out, 67324752 as Long)
            zipPush16(out, 20 as Long)
            zipPush16(out, 0 as Long)
            zipPush16(out, method as Long)
            zipPush16(out, 0 as Long)
            zipPush16(out, 0 as Long)
            zipPush32(out, crc)
            zipPush32(out, packed.length() as Long)
            zipPush32(out, pending.content.length() as Long)
            zipPush16(out, pending.name.length() as Long)
            zipPush16(out, 0 as Long)
            zipPushText(out, pending.name)
            zipPushText(out, packed.toString())
            String? comment = null
            ZipEntry entry = new ZipEntry(pending.name, pending.content.length() as Long,
                packed.length() as Long, crc, 0 as Long, pending.directory, comment)
            central.push(new ZipCentral(entry, method, offset))
            index = index + 1
        }
        Long centralOffset = out.length() as Long
        index = 0
        while index < central.length() {
            ZipCentral item = central.get(index)
            ZipEntry entry = item.entry
            zipPush32(out, 33639248 as Long)
            zipPush16(out, 20 as Long)
            zipPush16(out, 20 as Long)
            zipPush16(out, 0 as Long)
            zipPush16(out, item.method as Long)
            zipPush16(out, 0 as Long)
            zipPush16(out, 0 as Long)
            zipPush32(out, entry.crc32())
            zipPush32(out, entry.compressedSize())
            zipPush32(out, entry.size())
            zipPush16(out, entry.name().length() as Long)
            zipPush16(out, 0 as Long)
            zipPush16(out, 0 as Long)
            zipPush16(out, 0 as Long)
            zipPush16(out, 0 as Long)
            if entry.isDirectory() { zipPush32(out, 16 as Long) } else { zipPush32(out, 0 as Long) }
            zipPush32(out, item.offset)
            zipPushText(out, entry.name())
            index = index + 1
        }
        Long centralSize = (out.length() as Long) - centralOffset
        zipPush32(out, 101010256 as Long)
        zipPush16(out, 0 as Long)
        zipPush16(out, 0 as Long)
        zipPush16(out, central.length() as Long)
        zipPush16(out, central.length() as Long)
        zipPush32(out, centralSize)
        zipPush32(out, centralOffset)
        String? archiveComment = self._options.getComment()
        if archiveComment == null {
            zipPush16(out, 0 as Long)
        } else {
            String archiveText = archiveComment as String
            zipPush16(out, archiveText.length() as Long)
            zipPushText(out, archiveText)
        }
        self._finished = true
        self._result = copy(out)
        return Ok(out)
    }

    Result<Unit, Error> writeTo(String path) {
        if path == null { throw "ZipWriter.writeTo: null path" }
        Result<Bytes, Error> data = self.finish()
        if data.isErr() { return Err(data.error()) }
        String parent = tarParent(path)
        if parent.length() > 0 { tarMkdirAll(parent) }
        Int rc = writeFileHexRaw(path, toHexFast(data.value()), false)
        if rc != 0 {
            return Err(new BasicError(ErrorKind.Io, "ZipWriter.writeTo: write failed"))
        }
        return Ok()
    }

    Int entryCount() { return self._pending.length() }
    Bool isFinished() { return self._finished }
    Bool isClosed() { return self._closed }

    Void close() {
        self._closed = true
    }
}

// ---------- ZipArchive ----------
class ZipArchive {
    final Bytes _data
    final ZipOptions _options
    List<ZipArchiveItem> _items
    Bool _closed

    private ZipArchive(Bytes data, ZipOptions options, List<ZipArchiveItem> items) {
        self._data = data
        self._options = options
        self._items = items
        self._closed = false
    }

    static Result<ZipArchive, Error> open(String path, ZipOptions options) {
        if path == null || options == null { throw "ZipArchive.open: null argument" }
        if fileExistsRaw(path) == 0 {
            return Err(new BasicError(ErrorKind.NotFound, "ZipArchive.open: file not found"))
        }
        String hex = readFileHexRaw(path)
        Int size = fileSizeRaw(path)
        if size > 0 && hex.length() != size * 2 {
            return Err(new BasicError(ErrorKind.Io, "ZipArchive.open: read failed"))
        }
        return ZipArchive.openBytesWithOptions(fromHex(hex), options)
    }

    static Result<ZipArchive, Error> openBytes(Bytes data) {
        return ZipArchive.openBytesWithOptions(data, new ZipOptions())
    }

    static Result<ZipArchive, Error> openBytesWithOptions(Bytes data, ZipOptions options) {
        if data == null || options == null { throw "ZipArchive.openBytes: null argument" }
        Int length = data.length()
        if length < 22 {
            return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: missing EOCD"))
        }
        Int eocd = -1
        Int probe = length - 22
        Int lowest = length - 65557
        if lowest < 0 { lowest = 0 }
        while probe >= lowest {
            if zipRead32(data, probe) == 101010256 as Long {
                eocd = probe
                break
            }
            probe = probe - 1
        }
        if eocd < 0 {
            return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: missing EOCD"))
        }
        Long entries = zipRead16(data, eocd + 10)
        Long centralSize = zipRead32(data, eocd + 12)
        Long centralOffset = zipRead32(data, eocd + 16)
        Long commentLength = zipRead16(data, eocd + 20)
        if entries == 65535 as Long || centralSize == 4294967295 as Long ||
           centralOffset == 4294967295 as Long {
            return Err(new BasicError(ErrorKind.Unsupported, "ZipArchive: zip64 is not supported"))
        }
        if eocd + 22 + (commentLength as Int) > length {
            return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: invalid EOCD"))
        }
        if centralOffset + centralSize > length as Long {
            return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: central directory out of range"))
        }
        List<ZipArchiveItem> items = []
        Long total = 0 as Long
        Int cursor = centralOffset as Int
        Int index = 0
        while index < entries as Int {
            if cursor + 46 > length {
                return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: truncated central directory"))
            }
            if zipRead32(data, cursor) != 33639248 as Long {
                return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: invalid central header"))
            }
            Long flags = zipRead16(data, cursor + 8)
            if (flags & 1 as Long) != 0 || (flags & 64 as Long) != 0 {
                return Err(new BasicError(ErrorKind.Unsupported, "ZipArchive: encrypted entries are not supported"))
            }
            Long method = zipRead16(data, cursor + 10)
            if method != 0 as Long && method != 8 as Long {
                return Err(new BasicError(ErrorKind.Unsupported, "ZipArchive: unsupported compression method"))
            }
            Long crc = zipRead32(data, cursor + 16)
            Long compressedSize = zipRead32(data, cursor + 20)
            Long size = zipRead32(data, cursor + 24)
            Long nameLength = zipRead16(data, cursor + 28)
            Long extraLength = zipRead16(data, cursor + 30)
            Long entryComment = zipRead16(data, cursor + 32)
            Long localOffset = zipRead32(data, cursor + 42)
            if compressedSize == 4294967295 as Long || size == 4294967295 as Long ||
               localOffset == 4294967295 as Long {
                return Err(new BasicError(ErrorKind.Unsupported, "ZipArchive: zip64 is not supported"))
            }
            Int nameStart = cursor + 46
            if nameStart + (nameLength as Int) > length {
                return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: truncated name"))
            }
            String name = data.slice(nameStart, nameStart + (nameLength as Int)).toString()
            Bool directory = name.length() > 0 &&
                name.substring(name.length() - 1, 1) == "/"
            if !zipNameSafe(name, directory) {
                return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: unsafe entry name"))
            }
            if size > options.getMaxEntryBytes() as Long {
                return Err(new BasicError(ErrorKind.InvalidArgument, "ZipArchive: entry exceeds maxEntryBytes"))
            }
            total = total + size
            if total > options.getMaxTotalBytes() as Long {
                return Err(new BasicError(ErrorKind.InvalidArgument, "ZipArchive: total exceeds maxTotalBytes"))
            }
            if localOffset + 30 as Long > length as Long {
                return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: local header out of range"))
            }
            Int local = localOffset as Int
            if zipRead32(data, local) != 67324752 as Long {
                return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: invalid local header"))
            }
            Long localMethod = zipRead16(data, local + 8)
            Long localNameLength = zipRead16(data, local + 26)
            Long localExtraLength = zipRead16(data, local + 28)
            if localMethod != method {
                return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: local method mismatch"))
            }
            Long dataStart = localOffset + 30 as Long + localNameLength + localExtraLength
            if dataStart + compressedSize > length as Long {
                return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: entry data out of range"))
            }
            String comment = null
            if entryComment > 0 {
                Int commentStart = cursor + 46 + (nameLength as Int) + (extraLength as Int)
                if commentStart + (entryComment as Int) > length {
                    return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: truncated comment"))
                }
                comment = data.slice(commentStart, commentStart + (entryComment as Int)).toString()
            }
            ZipEntry entry = new ZipEntry(name, size, compressedSize, crc, 0 as Long, directory, comment)
            items.push(new ZipArchiveItem(entry, method as Int, dataStart))
            cursor = cursor + 46 + (nameLength as Int) + (extraLength as Int) + (entryComment as Int)
            index = index + 1
        }
        return Ok(new ZipArchive(copy(data), options.copy(), items))
    }

    List<ZipEntry> entries() {
        List<ZipEntry> result = []
        Int index = 0
        while index < self._items.length() {
            result.push(self._items.get(index).entry)
            index = index + 1
        }
        return result
    }

    ZipEntry? getOrNull(String name) {
        if name == null { throw "ZipArchive.getOrNull: null name" }
        Int index = 0
        while index < self._items.length() {
            if self._items.get(index).entry.name() == name {
                return self._items.get(index).entry
            }
            index = index + 1
        }
        return null
    }

    Result<Bytes, Error> readEntry(ZipEntry entry) {
        if entry == null { throw "ZipArchive.readEntry: null entry" }
        if self._closed {
            return Err(new BasicError(ErrorKind.Unavailable, "ZipArchive.readEntry: archive is closed"))
        }
        Int index = 0
        while index < self._items.length() {
            ZipArchiveItem item = self._items.get(index)
            if item.entry == entry {
                return self.readItem(item)
            }
            index = index + 1
        }
        return Err(new BasicError(ErrorKind.NotFound, "ZipArchive.readEntry: entry not found"))
    }

    Result<Bytes, Error> readEntryByName(String name) {
        if name == null { throw "ZipArchive.readEntryByName: null name" }
        ZipEntry? entry = self.getOrNull(name)
        if entry == null {
            return Err(new BasicError(ErrorKind.NotFound, "ZipArchive.readEntryByName: entry not found"))
        }
        return self.readEntry(entry as ZipEntry)
    }

    Result<Bytes, Error> readItem(ZipArchiveItem item) {
        ZipEntry entry = item.entry
        if entry.isDirectory() { return Ok(Bytes.fromString("")) }
        Int start = item.dataOffset as Int
        Int end = start + entry.compressedSize() as Int
        Bytes packed = self._data.slice(start, end)
        Bytes content = packed
        if item.method == 8 {
            Result<Bytes, Error> inflated = Deflate.decompressWithLimit(packed, self._options.getMaxEntryBytes())
            if inflated.isErr() { return Err(inflated.error()) }
            content = inflated.value()
        }
        if content.length() as Long != entry.size() {
            return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: size mismatch"))
        }
        if self._options.isVerifyCrc() {
            Long crc = Checksum.compute(ChecksumAlgorithm.Crc32, content)
            if crc != entry.crc32() {
                return Err(new BasicError(ErrorKind.DataCorrupted, "ZipArchive: crc mismatch"))
            }
        }
        return Ok(content)
    }

    Result<Unit, Error> extractTo(String directory) {
        if directory == null { throw "ZipArchive.extractTo: null directory" }
        if self._closed {
            return Err(new BasicError(ErrorKind.Unavailable, "ZipArchive.extractTo: archive is closed"))
        }
        tarMkdirAll(directory)
        String base = directory
        if base.substring(base.length() - 1, 1) == "/" {
            base = base.substring(0, base.length() - 1)
        }
        Int index = 0
        while index < self._items.length() {
            ZipArchiveItem item = self._items.get(index)
            ZipEntry entry = item.entry
            String target = base + "/" + entry.name()
            if entry.isDirectory() {
                tarMkdirAll(target)
            } else {
                String parent = tarParent(target)
                if parent.length() > 0 { tarMkdirAll(parent) }
                Result<Bytes, Error> content = self.readItem(item)
                if content.isErr() { return Err(content.error()) }
                Int rc = writeFileHexRaw(target, toHexFast(content.value()), false)
                if rc != 0 {
                    return Err(new BasicError(ErrorKind.Io, "ZipArchive.extractTo: write failed"))
                }
            }
            index = index + 1
        }
        return Ok()
    }

    Bool isOpen() { return !self._closed }

    Void close() {
        self._closed = true
    }
}
