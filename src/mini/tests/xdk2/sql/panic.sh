#!/bin/sh
# xdk.sql contract panics: invalid parameters, row bounds, result shape, options.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/panic.x" <<'X'
import xdk.sql
static Int main(String[] args) {
    String name = args.get(0)
    if name == "indexed" {
        SqlParameter.indexed(0, SqlValue.nullValue())
    } else if name == "named" {
        SqlParameter.named(" ", SqlValue.nullValue())
    } else if name == "row" {
        List<SqlValue> values = []
        values.push(SqlValue.ofInt(1))
        SqlRow row = new SqlRow(values)
        row.get(2)
    } else if name == "result" {
        List<SqlColumn> columns = []
        columns.push(new SqlColumn("a", "INT", false))
        List<SqlValue> values = []
        values.push(SqlValue.ofInt(1))
        values.push(SqlValue.ofInt(2))
        List<SqlRow> rows = []
        rows.push(new SqlRow(values))
        SqlResult result = new SqlResult(columns, rows, 0, true)
    } else if name == "options" {
        SqlOptions options = new SqlOptions()
        options.maxRows(-1)
    } else if name == "first" {
        SqlStatement statement = new SqlStatement("select ?")
        statement.withParameter(SqlParameter.indexed(2, SqlValue.ofInt(1)))
    } else if name == "mixed" {
        SqlStatement statement = new SqlStatement("select ?, :x")
        statement = statement.bind(SqlValue.ofInt(1))
        statement.withParameter(SqlParameter.named("x", SqlValue.ofInt(2)))
    } else if name == "column" {
        SqlColumn column = new SqlColumn("", "INT", false)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || {
    cat "$TMP/build.err" >&2
    echo "sql panic: build failed" >&2
    exit 1
}

check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && {
        echo "sql panic: $name did not fail" >&2
        exit 1
    }
    grep -q "$marker" "$TMP/$name.err" || {
        echo "sql panic: $name missing marker '$marker'" >&2
        cat "$TMP/$name.err" >&2
        exit 1
    }
}

check_panic "indexed" "SqlParameter.indexed: parameterIndex < 1"
check_panic "named" "SqlParameter.named: empty name"
check_panic "row" "SqlRow.get: columnIndex out of range"
check_panic "result" "SqlResult: row length mismatch"
check_panic "options" "SqlOptions.maxRows: negative"
check_panic "first" "first index must be 1"
check_panic "mixed" "mixed styles"
check_panic "column" "SqlColumn: empty name"

echo "sql_panic: PASS"
