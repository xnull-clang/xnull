#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cp "$HERE/MemoryFixture.x" "$TMP/MemoryFixture.x"
cat > "$TMP/panic.x" <<'X'
import xdk.db
import xdk.sql
import MemoryFixture
static Migration panicUp() {
    List<SqlStatement> up = []
    up.push(new SqlStatement("SELECT 1"))
    return new Migration("1.0", "panic", up)
}
static Database panicDatabase() {
    Map<String, String> options = [:]
    DatabaseConfig config = new DatabaseConfig("panic", "memory://panic", options, null, 0, 2, 1000, 0, 0, 0, 0, true, true, null)
    DatabasePool pool = new DatabasePool(new MemoryDriver(), config, "memory")
    return new Database(pool)
}
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
    } else if name == "migrationVersion" {
        List<SqlStatement> up = []
        up.push(new SqlStatement("SELECT 1"))
        Migration migration = new Migration("1.02", "v", up)
    } else if name == "migrationEmptyUp" {
        List<SqlStatement> up = []
        Migration migration = new Migration("1.0", "v", up)
    } else if name == "migrationName" {
        List<SqlStatement> up = []
        up.push(new SqlStatement("SELECT 1"))
        Migration migration = new Migration("1.0", "", up)
    } else if name == "migrationMultiline" {
        List<SqlStatement> up = []
        up.push(new SqlStatement("SELECT 1"))
        Migration migration = new Migration("1.0", "a\nb", up)
    } else if name == "migrationNullUp" {
        Migration migration = new Migration("1.0", "v", null)
    } else if name == "migrationNullDown" {
        List<SqlStatement> up = []
        up.push(new SqlStatement("SELECT 1"))
        List<SqlStatement> down = []
        down.push(null)
        Migration migration = new Migration("1.0", "v", up, down)
    } else if name == "migrationTable" {
        Database database = panicDatabase()
        MigrationRunner runner = new MigrationRunner(database, "bad name")
    } else if name == "migrationTimeout" {
        Database database = panicDatabase()
        MigrationRunner runner = new MigrationRunner(database, "ok_history", -1)
    } else if name == "migrationLease" {
        Database database = panicDatabase()
        MigrationRunner runner = new MigrationRunner(database, "ok_history", 30000, 999)
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
check_panic migrationVersion "Migration: version leading zero"
check_panic migrationEmptyUp "Migration: empty up statements"
check_panic migrationName "Migration: invalid name"
check_panic migrationMultiline "Migration: name must be single-line"
check_panic migrationNullUp "Migration: null argument"
check_panic migrationNullDown "Migration: null down statement"
check_panic migrationTable "MigrationRunner: invalid history table"
check_panic migrationTimeout "MigrationRunner: negative lock timeout"
check_panic migrationLease "MigrationRunner: lock lease below 1000"
echo "db_panic: PASS"
