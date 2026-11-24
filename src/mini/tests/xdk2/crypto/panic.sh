#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.crypto
import xdk.crypto
import xdk.bytes
import xdk.io
import xdk.tasks
import xdk.errors

static Bytes bytesOf(String text) { return Bytes.fromString(text) }

static Int main(String[] args) {
    String name = args.get(0)
    if name == "sha3" {
        Bytes ignored = Hash.digest(HashAlgorithm.Sha3_256, bytesOf("abc"))
    } else if name == "sm3" {
        Bytes ignored = Hash.digest(HashAlgorithm.Sm3, bytesOf("abc"))
    } else if name == "blake" {
        String ignored = Hash.hex(HashAlgorithm.Blake3, bytesOf("abc"))
    } else if name == "hmacSm3" {
        Bytes ignored = Hmac.sign(HashAlgorithm.Sm3, bytesOf("k"), bytesOf("d"))
    } else if name == "digestNull" {
        Bytes ignored = Hash.digest(HashAlgorithm.Sha256, null)
    } else if name == "hashReaderNull" {
        Reader reader = new Reader(bytesOf("x"))
        Result<Bytes, Error> result = Hash.hashReader(null, HashAlgorithm.Sha256, reader)
    } else if name == "hmacNull" {
        Bytes ignored = Hmac.sign(HashAlgorithm.Sha256, null, bytesOf("d"))
    } else if name == "checksumNull" {
        Long ignored = Checksum.compute(ChecksumAlgorithm.Crc32, null)
    } else if name == "ctNull" {
        Bool ignored = ConstantTime.equals(null, bytesOf("x"))
    } else if name == "ctZeroNull" {
        Bool ignored = ConstantTime.isZero(null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || {
    cat "$TMP/build.err" >&2
    exit 1
}
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && {
        echo "crypto panic: $name did not fail" >&2
        exit 1
    }
    grep -Fq "$marker" "$TMP/$name.err" || {
        echo "crypto panic: $name missing marker '$marker'" >&2
        cat "$TMP/$name.err" >&2
        exit 1
    }
}
check_panic sha3 "Hash: Unsupported algorithm: sha3-256"
check_panic sm3 "Hash: Unsupported algorithm: sm3"
check_panic blake "Hash: Unsupported algorithm: blake3"
check_panic hmacSm3 "Hash: Unsupported algorithm: sm3"
check_panic digestNull "Hash.digest: null data"
check_panic hashReaderNull "Hash.hashReader: null argument"
check_panic hmacNull "Hmac.sign: null argument"
check_panic checksumNull "Checksum.compute: null data"
check_panic ctNull "ConstantTime.equals: null argument"
check_panic ctZeroNull "ConstantTime.isZero: null data"
echo "crypto_panic: PASS"
