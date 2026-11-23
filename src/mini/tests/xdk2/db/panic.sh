#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
import xdk.db
import xdk.sql
static DatabaseConfig makeConfig(String name, String uri, Map<String, String> options, Int minimum, Int maximum, Long acquire, Long validation, Long leak) {
    return new DatabaseConfig(name, uri, options, null, minimum, maximum,
        acquire, 0, 0, validation, leak, true, true, null)
}
static Int main(String[] args) {
    String name = args.get(0)
    Map<String, String> options = [:]
    if name == "badName" {
        DatabaseConfig config = DatabaseConfig.of("1bad", "postgres://x")
    } else if name == "longName" {
        DatabaseConfig config = DatabaseConfig.of("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnop", "postgres://x")
    } else if name == "emptyUri" {
        DatabaseConfig config = DatabaseConfig.of("app", " ")
    } else if name == "maxPool" {
        DatabaseConfig config = makeConfig("app", "postgres://x", options, 0, 0, 1, 0, 0)
    } else if name == "minIdle" {
        DatabaseConfig config = makeConfig("app", "postgres://x", options, 5, 2, 1, 0, 0)
    } else if name == "negativeTimeout" {
        DatabaseConfig config = makeConfig("app", "postgres://x", options, 0, 10, -1, 0, 0)
    } else if name == "validationTimeout" {
        DatabaseConfig config = makeConfig("app", "postgres://x", options, 0, 10, 1000, 1000, 0)
    } else if name == "leakThreshold" {
        DatabaseConfig config = makeConfig("app", "postgres://x", options, 0, 10, 1000, 0, 500)
    } else if name == "reservedOption" {
        options.put(isolationOpenOptionKey(), "x")
        DatabaseConfig config = makeConfig("app", "postgres://x", options, 0, 10, 1000, 0, 0)
    } else if name == "optionKey" {
        options.put("bad key", "x")
        DatabaseConfig config = makeConfig("app", "postgres://x", options, 0, 10, 1000, 0, 0)
    } else if name == "optionValue" {
        options.put("key", "a\nb")
        DatabaseConfig config = makeConfig("app", "postgres://x", options, 0, 10, 1000, 0, 0)
    } else if name == "statsTotal" {
        DatabasePoolStats stats = new DatabasePoolStats("p", 10, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)
    } else if name == "batchNull" {
        DbBatch batch = new DbBatch()
        batch.add(null)
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
        echo "db panic: $name did not fail" >&2
        exit 1
    }
    grep -q "$marker" "$TMP/$name.err" || {
        echo "db panic: $name missing marker '$marker'" >&2
        cat "$TMP/$name.err" >&2
        exit 1
    }
}
check_panic badName "DatabaseConfig: invalid name"
check_panic longName "DatabaseConfig: invalid name"
check_panic emptyUri "DatabaseConfig: empty connectionUri"
check_panic maxPool "DatabaseConfig: maximumPoolSize < 1"
check_panic minIdle "DatabaseConfig: invalid minimumIdle"
check_panic negativeTimeout "DatabaseConfig: negative timeout"
check_panic validationTimeout "DatabaseConfig: validationTimeout must be less than acquireTimeout"
check_panic leakThreshold "DatabaseConfig: leak threshold below 1000"
check_panic reservedOption "DatabaseConfig: reserved isolation option"
check_panic optionKey "DatabaseConfig: invalid option key"
check_panic optionValue "DatabaseConfig: invalid option value"
check_panic statsTotal "DatabasePoolStats: inconsistent total"
check_panic batchNull "DbBatch.add: null statement"
echo "db_panic: PASS"
