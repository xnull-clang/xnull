// xdk.compress —— L4 gzip/zlib/deflate 核心（M18.2）
//
// 本文件实现 4/14 类型：CompressionLevel、Gzip、Zlib、Deflate。
// Zstd/Lz4/Brotli/Zip/Tar 仍为 planned。
// 稳定性：preview。合同见 docs/design/utils/compress/。
package xdk.compress
import xdk.errors
import xdk.bytes

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
