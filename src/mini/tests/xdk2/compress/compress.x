package app.compress
import xdk.compress
import xdk.bytes
import xdk.errors

static Bytes longPayload() {
    Bytes data = Bytes.fromString("")
    Int index = 0
    while index < 70000 {
        data.push((index * 31 + 7) % 251)
        index = index + 1
    }
    return data
}

static Bytes binaryPayload() {
    return fromHex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f" +
        "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f" +
        "404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f" +
        "606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f" +
        "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f" +
        "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf" +
        "c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf" +
        "e0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
}

static Bool sameBytes(Bytes left, Bytes right) {
    if left.length() != right.length() { return false }
    Int index = 0
    while index < left.length() {
        if left.get(index) != right.get(index) { return false }
        index = index + 1
    }
    return true
}

static Bool gzipRound(Bytes data) {
    Result<Bytes, Error> compressed = Gzip.compress(data, CompressionLevel.Default)
    if compressed.isErr() { return false }
    Result<Bytes, Error> restored = Gzip.decompress(compressed.value())
    return restored.isOk() && sameBytes(data, restored.value())
}

static Bool zlibRound(Bytes data) {
    Result<Bytes, Error> compressed = Zlib.compress(data, CompressionLevel.Default)
    if compressed.isErr() { return false }
    Result<Bytes, Error> restored = Zlib.decompress(compressed.value())
    return restored.isOk() && sameBytes(data, restored.value())
}

static Bool deflateRound(Bytes data) {
    Result<Bytes, Error> compressed = Deflate.compress(data, CompressionLevel.Default)
    if compressed.isErr() { return false }
    Result<Bytes, Error> restored = Deflate.decompress(compressed.value())
    return restored.isOk() && sameBytes(data, restored.value())
}

static Int main() {
    Bytes empty = Bytes.fromString("")
    Bytes shortText = Bytes.fromString("hello compress")
    Bytes longText = longPayload()
    Bytes binary = binaryPayload()

    print("round=" + str(gzipRound(empty)) + "," + str(zlibRound(empty)) + "," +
        str(deflateRound(empty)) + "," + str(gzipRound(shortText)) + "," +
        str(zlibRound(shortText)) + "," + str(deflateRound(shortText)))
    print("long=" + str(gzipRound(longText)) + "," + str(zlibRound(longText)) + "," +
        str(deflateRound(longText)) + "," + str(longText.length()))
    print("binary=" + str(gzipRound(binary)) + "," + str(zlibRound(binary)) + "," +
        str(deflateRound(binary)) + "," + str(binary.length()))

    Result<Bytes, Error> gzipBest = Gzip.compress(longText, CompressionLevel.Maximum)
    Result<Bytes, Error> gzipFast = Gzip.compress(longText, CompressionLevel.Fastest)
    Result<Bytes, Error> zlibBest = Zlib.compress(longText, CompressionLevel.Maximum)
    Result<Bytes, Error> zlibFast = Zlib.compress(longText, CompressionLevel.Fastest)
    Result<Bytes, Error> deflateBest = Deflate.compress(longText, CompressionLevel.Maximum)
    Result<Bytes, Error> deflateFast = Deflate.compress(longText, CompressionLevel.Fastest)
    print("level=" + str(gzipBest.value().length() <= gzipFast.value().length()) + "," +
        str(zlibBest.value().length() <= zlibFast.value().length()) + "," +
        str(deflateBest.value().length() <= deflateFast.value().length()))

    print("magic=" + str(Gzip.isGzip(gzipBest.value())) + "," +
        str(Zlib.isZlib(zlibBest.value())) + "," + str(Gzip.isGzip(zlibBest.value())) + "," +
        str(Zlib.isZlib(gzipBest.value())) + "," + str(Gzip.isGzip(shortText)))

    Result<Bytes, Error> limit = Gzip.decompressWithLimit(gzipBest.value(), 8)
    Result<Bytes, Error> zlimit = Zlib.decompressWithLimit(zlibBest.value(), 8)
    Result<Bytes, Error> dlimit = Deflate.decompressWithLimit(deflateBest.value(), 8)
    print("limit=" + errorKindName(limit.error().kind()) + "," +
        errorKindName(zlimit.error().kind()) + "," + errorKindName(dlimit.error().kind()))

    Bytes corrupt = fromHex("1f8b08000000000000ff")
    Result<Bytes, Error> badGzip = Gzip.decompress(corrupt)
    Result<Bytes, Error> badZlib = Zlib.decompress(fromHex("789c00"))
    Result<Bytes, Error> badDeflate = Deflate.decompress(fromHex("ffffffff"))
    print("corrupt=" + errorKindName(badGzip.error().kind()) + "," +
        errorKindName(badZlib.error().kind()) + "," + errorKindName(badDeflate.error().kind()))

    Result<Bytes, Error> emptyGzip = Gzip.decompress(empty)
    Result<Bytes, Error> emptyZlib = Zlib.decompress(empty)
    Result<Bytes, Error> emptyDeflate = Deflate.decompress(empty)
    print("empty=" + errorKindName(emptyGzip.error().kind()) + "," +
        errorKindName(emptyZlib.error().kind()) + "," + errorKindName(emptyDeflate.error().kind()))

    Result<Bytes, Error> emptyOut = Gzip.decompressWithLimit(
        Gzip.compress(empty, CompressionLevel.Default).value(), 0)
    print("empty-out=" + str(emptyOut.isOk()) + "," + str(emptyOut.value().length()))
    return 0
}
