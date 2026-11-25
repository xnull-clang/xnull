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
echo "compress_panic: PASS"
