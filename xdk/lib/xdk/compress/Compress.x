// xdk.compress —— L4 gzip/zlib/deflate 核心（M18.2）
//
// 本文件实现 4/14 类型：CompressionLevel、Gzip、Zlib、Deflate。
// Zstd/Lz4/Brotli/Zip/Tar 仍为 planned。
// 稳定性：preview。合同见 docs/design/utils/compress/。
package xdk.compress
import xdk.errors
import xdk.bytes
import xdk.text

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
