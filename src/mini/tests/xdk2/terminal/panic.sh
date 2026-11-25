#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.terminal
import xdk.terminal
import xdk.errors
import xdk.bytes

class NullWriter implements Writer {
    Bool isOpen() { return true }
    Result<Unit, Error> writeAll(Context context, Bytes data) { return Ok() }
    Result<Unit, Error> flush() { return Ok() }
}

static Int main(String[] args) {
    String name = args.get(0)
    if name == "basicLow" {
        Color value = Color.basic(-1)
    } else if name == "basicHigh" {
        Color value = Color.basic(16)
    } else if name == "indexedLow" {
        Color value = Color.indexed(-1)
    } else if name == "indexedHigh" {
        Color value = Color.indexed(256)
    } else if name == "rgbLow" {
        Color value = Color.rgb(-1, 0, 0)
    } else if name == "rgbHigh" {
        Color value = Color.rgb(0, 0, 256)
    } else if name == "basicAccessor" {
        Int value = Color.rgb(1, 2, 3).basicIndex()
    } else if name == "indexAccessor" {
        Int value = Color.red().index()
    } else if name == "rgbAccessor" {
        Int value = Color.red().redChannel()
    } else if name == "ansiBoldNull" {
        String value = Ansi.bold(null)
    } else if name == "ansiFgNull" {
        String value = Ansi.fg(null, "x")
    } else if name == "ansiColor256" {
        String value = Ansi.color256(256, "x")
    } else if name == "ansiRgb" {
        String value = Ansi.rgb(0, 0, 256, "x")
    } else if name == "ansiCursor" {
        String value = Ansi.cursorUp(0)
    } else if name == "styleFg" {
        Style style = new Style()
        Style value = style.fg(null)
    } else if name == "styleBg" {
        Style style = new Style()
        Style value = style.bg(null)
    } else if name == "styleRender" {
        Style style = new Style()
        String value = style.render(null)
    } else if name == "terminalContext" {
        Terminal value = new Terminal(null, new NullWriter(), false, 0, 0)
    } else if name == "terminalWriter" {
        Terminal value = new Terminal(Context.background(), null, false, 0, 0)
    } else if name == "terminalWidth" {
        Terminal value = new Terminal(Context.background(), new NullWriter(), false, -1, 0)
    } else if name == "terminalHeight" {
        Terminal value = new Terminal(Context.background(), new NullWriter(), false, 0, -1)
    } else if name == "tableColumns" {
        Table value = new Table(null)
    } else if name == "tableMaxWidth" {
        List<String> columns = []
        Table value = new Table(columns, -1)
    } else if name == "tableRowNull" {
        List<String> columns = ["A"]
        Table table = new Table(columns)
        List<String> cells = []
        table.addRow(null)
    } else if name == "tableRowCount" {
        List<String> columns = ["A", "B"]
        Table table = new Table(columns)
        List<String> cells = ["only"]
        table.addRow(cells)
    } else if name == "tableCellNull" {
        List<String> columns = ["A"]
        Table table = new Table(columns)
        List<String> cells = []
        cells.push(null)
        table.addRow(cells)
    } else if name == "tableCellNewline" {
        List<String> columns = ["A"]
        Table table = new Table(columns)
        List<String> cells = ["a\nb"]
        table.addRow(cells)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "terminal panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "terminal panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic basicLow "Color.basic: index out of range"
check_panic basicHigh "Color.basic: index out of range"
check_panic indexedLow "Color.indexed: index out of range"
check_panic indexedHigh "Color.indexed: index out of range"
check_panic rgbLow "Color.rgb: channel out of range"
check_panic rgbHigh "Color.rgb: channel out of range"
check_panic basicAccessor "Color.basicIndex: not basic"
check_panic indexAccessor "Color.index: not indexed"
check_panic rgbAccessor "Color.redChannel: not rgb"
check_panic ansiBoldNull "Ansi.bold: null text"
check_panic ansiFgNull "Ansi.fg: null argument"
check_panic ansiColor256 "Ansi.color256: index out of range"
check_panic ansiRgb "Ansi.rgb: channel out of range"
check_panic ansiCursor "Ansi.cursorUp: rows < 1"
check_panic styleFg "Style.fg: null color"
check_panic styleBg "Style.bg: null color"
check_panic styleRender "Style.render: null text"
check_panic terminalContext "Terminal: null context/writer"
check_panic terminalWriter "Terminal: null context/writer"
check_panic terminalWidth "Terminal: negative dimension"
check_panic terminalHeight "Terminal: negative dimension"
check_panic tableColumns "Table: null columns"
check_panic tableMaxWidth "Table: negative maxWidth"
check_panic tableRowNull "Table.addRow: null cells"
check_panic tableRowCount "Table.addRow: cell count does not match columns"
check_panic tableCellNull "Table.addRow: null cell"
check_panic tableCellNewline "Table.addRow: newline in cell"
echo "terminal_panic: PASS"
