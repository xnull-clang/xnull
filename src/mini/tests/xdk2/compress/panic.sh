#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.compress
import xdk.compress
import xdk.errors
import xdk.bytes

static Int main(String[] args) {
    String name = args.get(0)
    Bytes data = Bytes.fromString("data")
    if name == "gzipCompressNull" {
        Result<Bytes, Error> value = Gzip.compress(null, CompressionLevel.Default)
    } else if name == "gzipDecompressNull" {
        Result<Bytes, Error> value = Gzip.decompress(null)
    } else if name == "gzipLimitNull" {
        Result<Bytes, Error> value = Gzip.decompressWithLimit(null, 16)
    } else if name == "zlibCompressNull" {
        Result<Bytes, Error> value = Zlib.compress(null, CompressionLevel.Default)
    } else if name == "zlibDecompressNull" {
        Result<Bytes, Error> value = Zlib.decompress(null)
    } else if name == "zlibLimitNull" {
        Result<Bytes, Error> value = Zlib.decompressWithLimit(null, 16)
    } else if name == "deflateCompressNull" {
        Result<Bytes, Error> value = Deflate.compress(null, CompressionLevel.Default)
    } else if name == "deflateDecompressNull" {
        Result<Bytes, Error> value = Deflate.decompress(null)
    } else if name == "deflateLimitNull" {
        Result<Bytes, Error> value = Deflate.decompressWithLimit(null, 16)
    } else if name == "tarNameEmpty" {
        List<TarEntry> entries = []
        TarEntry entry = new TarEntry("", data, 420, 0 as Long, false)
    } else if name == "tarContentNull" {
        TarEntry entry = new TarEntry("a", null, 420, 0 as Long, false)
    } else if name == "tarMode" {
        TarEntry entry = new TarEntry("a", data, 5000, 0 as Long, false)
    } else if name == "tarTime" {
        TarEntry entry = new TarEntry("a", data, 420, -1 as Long, false)
    } else if name == "tarAbsolute" {
        TarEntry entry = new TarEntry("/a", data, 420, 0 as Long, false)
    } else if name == "tarParent" {
        TarEntry entry = new TarEntry("../a", data, 420, 0 as Long, false)
    } else if name == "tarBackslash" {
        TarEntry entry = new TarEntry("a\\b", data, 420, 0 as Long, false)
    } else if name == "tarFileSlash" {
        TarEntry entry = new TarEntry("a/", data, 420, 0 as Long, false)
    } else if name == "tarDirectorySlash" {
        TarEntry entry = new TarEntry("a", data, 420, 0 as Long, true)
    } else if name == "tarDirectoryContent" {
        TarEntry entry = new TarEntry("a/", data, 420, 0 as Long, true)
    } else if name == "tarWriteNull" {
        Result<Bytes, Error> value = Tar.write(null)
    } else if name == "tarReadNull" {
        Result<List<TarEntry>, Error> value = Tar.read(null)
    } else if name == "tarReadLimitEntries" {
        Result<List<TarEntry>, Error> value = Tar.readWithLimits(data, 0, 10)
    } else if name == "tarReadLimitBytes" {
        Result<List<TarEntry>, Error> value = Tar.readWithLimits(data, 10, 0)
    } else if name == "tarIsNull" {
        Bool value = Tar.isTar(null)
    } else if name == "tarWriteToNull" {
        List<TarEntry> entries = []
        Result<Unit, Error> value = Tar.writeTo(null, entries)
    } else if name == "tarReadFromNull" {
        Result<List<TarEntry>, Error> value = Tar.readFrom(null)
    } else if name == "tarExtractDirNull" {
        List<TarEntry> entries = []
        Result<Unit, Error> value = Tar.extractTo(null, entries)
    } else if name == "tarExtractEntriesNull" {
        Result<Unit, Error> value = Tar.extractTo("/tmp", null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "compress panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "compress panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic gzipCompressNull "Gzip.compress: null data"
check_panic gzipDecompressNull "Gzip.decompressWithLimit: null data"
check_panic gzipLimitNull "Gzip.decompressWithLimit: null data"
check_panic zlibCompressNull "Zlib.compress: null data"
check_panic zlibDecompressNull "Zlib.decompressWithLimit: null data"
check_panic zlibLimitNull "Zlib.decompressWithLimit: null data"
check_panic deflateCompressNull "Deflate.compress: null data"
check_panic deflateDecompressNull "Deflate.decompressWithLimit: null data"
check_panic deflateLimitNull "Deflate.decompressWithLimit: null data"
check_panic tarNameEmpty "TarEntry: empty name"
check_panic tarContentNull "TarEntry: null content"
check_panic tarMode "TarEntry: mode out of range"
check_panic tarTime "TarEntry: negative time"
check_panic tarAbsolute "TarEntry: absolute name"
check_panic tarParent "TarEntry: parent segment"
check_panic tarBackslash "TarEntry: invalid name"
check_panic tarFileSlash "TarEntry: file name must not end with slash"
check_panic tarDirectorySlash "TarEntry: directory name must end with slash"
check_panic tarDirectoryContent "TarEntry: directory content must be empty"
check_panic tarWriteNull "Tar.write: null entries"
check_panic tarReadNull "Tar.readWithLimits: null data"
check_panic tarIsNull "Tar.isTar: null data"
check_panic tarWriteToNull "Tar.writeTo: null path"
check_panic tarReadFromNull "Tar.readFrom: null path"
check_panic tarExtractDirNull "Tar.extractTo: null argument"
check_panic tarExtractEntriesNull "Tar.extractTo: null argument"
echo "compress_panic: PASS"
