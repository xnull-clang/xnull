#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
import xdk.cache
static Int main(String[] args) {
    String name = args.get(0)
    if name == "maxEntries" {
        CacheOptions options = new CacheOptions()
        options.maxEntries(0)
    } else if name == "maxWeight" {
        CacheOptions options = new CacheOptions()
        options.maxWeight(0)
    } else if name == "ttl" {
        CacheOptions options = new CacheOptions()
        options.defaultTtlMillis(-1)
    } else if name == "stats" {
        CacheStats stats = new CacheStats(-1, 0, 0, 0, 0, 0, 0, 0)
    } else if name == "nullKey" {
        CacheOptions options = new CacheOptions()
        Cache<String, Int> cache = new Cache<String, Int>(options)
        cache.get(null)
    } else if name == "weight" {
        CacheOptions options = new CacheOptions()
        Cache<String, Int> cache = new Cache<String, Int>(options)
        cache.putWeighted("a", 1, 0, 0)
    } else if name == "negativeTtl" {
        CacheOptions options = new CacheOptions()
        Cache<String, Int> cache = new Cache<String, Int>(options)
        cache.putWithTtl("a", 1, -1)
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
        echo "cache panic: $name did not fail" >&2
        exit 1
    }
    grep -q "$marker" "$TMP/$name.err" || {
        echo "cache panic: $name missing marker '$marker'" >&2
        cat "$TMP/$name.err" >&2
        exit 1
    }
}
check_panic maxEntries "CacheOptions.maxEntries: < 1"
check_panic maxWeight "CacheOptions.maxWeight: < 1"
check_panic ttl "CacheOptions.defaultTtlMillis: negative"
check_panic stats "CacheStats: negative counter"
check_panic nullKey "Cache.get: null key"
check_panic weight "Cache.putWeighted: weight < 1"
check_panic negativeTtl "Cache.putWithTtl: negative ttl"
echo "cache_panic: PASS"
