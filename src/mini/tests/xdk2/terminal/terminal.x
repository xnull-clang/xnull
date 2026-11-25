package xdk2.terminal
import xdk.terminal
import xdk.errors
import xdk.bytes

static Error writerUnavailable(String message) {
    return new BasicError(ErrorKind.Unavailable, message)
}

static Error writerIo(String message) {
    return new BasicError(ErrorKind.Io, message)
}

class MemoryWriter implements Writer {
    Bytes data
    Bool open
    Bool fail
    Int flushes

    MemoryWriter() {
        self.data = Bytes.fromString("")
        self.open = true
        self.fail = false
        self.flushes = 0
    }

    Bool isOpen() { return self.open }

    Result<Unit, Error> writeAll(Context context, Bytes source) {
        if !self.open {
            return Err(writerUnavailable("writer closed"))
        }
        if self.fail {
            return Err(writerIo("writer failed"))
        }
        Int index = 0
        while index < source.length() {
            self.data.push(source.get(index))
            index = index + 1
        }
        return Ok()
    }

    Result<Unit, Error> flush() {
        self.flushes = self.flushes + 1
        if self.fail {
            return Err(writerIo("flush failed"))
        }
        return Ok()
    }
}

static String oneLine(String text) {
    return text.replace("\n", "/")
}

static Int main() {
    Color basic = Color.red()
    Color indexed = Color.indexed(196)
    Color rgb = Color.rgb(255, 128, 0)
    print("color=" + basic.describe() + "," + indexed.describe() + "," + rgb.describe() +
        "," + str(basic.isBasic()) + "," + str(indexed.isIndexed()) + "," +
        str(rgb.isRgb()) + "," + str(basic.basicIndex()) + "," + str(indexed.index()) +
        "," + str(rgb.redChannel()) + "," + str(rgb.greenChannel()) + "," +
        str(rgb.blueChannel()))
    print("color-equals=" + str(Color.red().equals(Color.basic(1))) + "," +
        str(Color.red().equals(Color.indexed(1))) + "," +
        str(Color.rgb(1, 2, 3).equals(Color.rgb(1, 2, 3))) + "," +
        str(Color.rgb(1, 2, 3).equals(Color.rgb(1, 2, 4))) + "," +
        str(Color.red().equals(null)))
    print("color-named=" + str(Color.brightWhite().basicIndex()) + "," +
        Color.brightWhite().toString() + "," + Color.black().toString())

    print("ansi=" + str(Ansi.reset() == "\x1b[0m") + "," +
        str(Ansi.bold("x") == "\x1b[1mx\x1b[0m") + "," +
        str(Ansi.fg(Color.red(), "x") == "\x1b[31mx\x1b[0m") + "," +
        str(Ansi.fg(Color.brightRed(), "x") == "\x1b[91mx\x1b[0m") + "," +
        str(Ansi.bg(Color.blue(), "x") == "\x1b[44mx\x1b[0m") + "," +
        str(Ansi.color256(196, "x") == "\x1b[38;5;196mx\x1b[0m") + "," +
        str(Ansi.rgb(1, 2, 3, "x") == "\x1b[38;2;1;2;3mx\x1b[0m") + "," +
        str(Ansi.cursorUp(2) == "\x1b[2A") + "," +
        str(Ansi.clearScreen() == "\x1b[2J\x1b[H"))

    Style plain = new Style()
    Style styled = plain.fg(Color.green()).boldOn().underlineOn()
    Style styledCopy = styled.copy()
    print("style=" + str(plain.isPlain()) + "," + str(styled.isPlain()) + "," +
        str(styled.equals(styledCopy)) + "," + str(styled.equals(plain)) + "," +
        str(styled.equals(null)) + "," + str(styled.render("ok").indexOf("\x1b[") >= 0) +
        "," + str(plain.render("ok") == "ok"))

    Context context = Context.background()
    MemoryWriter writer = new MemoryWriter()
    Terminal plainTerminal = new Terminal(context, writer, false, 80, 24)
    Result<Unit, Error> plainWrite = plainTerminal.write(Ansi.bold("hello"))
    String writtenText = writer.data.toString()
    print("terminal-plain=" + str(plainWrite.isOk()) + "," + writtenText + "," +
        str(plainTerminal.isTerminal()) + "," + str(plainTerminal.width()) + "," +
        str(plainTerminal.height()))
    Result<Unit, Error> plainClear = plainTerminal.clear()
    print("terminal-plain-clear=" + str(plainClear.isOk()) + "," +
        str(writer.data.length()) + "," + str(writer.flushes))
    Result<Unit, Error> flush = plainTerminal.flush()
    Result<Unit, Error> line = plainTerminal.writeLine("line")
    Result<Unit, Error> closed = plainTerminal.close()
    Result<Unit, Error> closedWrite = plainTerminal.write("late")
    print("terminal-close=" + str(flush.isOk()) + "," + str(writer.flushes) + "," +
        str(line.isOk()) + "," + str(closed.isOk()) + "," +
        errorKindName(closedWrite.error().kind()) + "," + str(writer.open))

    MemoryWriter terminalWriter = new MemoryWriter()
    Terminal tty = new Terminal(context, terminalWriter, true, 100, 40)
    tty.write(Ansi.bold("x"))
    Result<Unit, Error> ttyClear = tty.clear()
    print("terminal-tty=" + str(terminalWriter.data.get(0) == 27) + "," +
        str(ttyClear.isOk()) + "," + str(terminalWriter.data.length() > 3) + "," +
        str(tty.width()) + "," + str(tty.height()))

    MemoryWriter brokenWriter = new MemoryWriter()
    brokenWriter.fail = true
    Terminal broken = new Terminal(context, brokenWriter, false, 0, 0)
    print("terminal-error=" + errorKindName(broken.write("x").error().kind()) + "," +
        errorKindName(broken.flush().error().kind()) + "," + str(broken.width()) + "," +
        str(broken.height()))

    List<String> columnNames = ["Name", "Status"]
    Table table = new Table(columnNames, 30)
    List<String> row = ["api", "ok"]
    table.addRow(row)
    String rendered = table.render()
    print("table=" + oneLine(rendered))
    print("table-info=" + str(table.rowCount()) + "," + str(table.columns().length()) +
        "," + table.columns().get(0) + "," + str(table.maxWidth()) + "," +
        str(rendered.indexOf("+------+--------+") == 0) + "," +
        str(rendered.indexOf("\n") > 0))

    List<String> emptyColumns = ["A", "B"]
    Table empty = new Table(emptyColumns)
    String emptyRendered = empty.render()
    print("table-empty=" + str(empty.rowCount()) + "," + oneLine(emptyRendered))

    List<String> narrowColumns = ["A", "B"]
    Table narrow = new Table(narrowColumns, 12)
    List<String> narrowRow = ["long", "value"]
    narrow.addRow(narrowRow)
    String narrowRendered = narrow.render()
    List<String> narrowLines = narrowRendered.split("\n")
    print("table-narrow=" + str(narrowLines.get(0).length() <= 12) + "," +
        str(narrowLines.get(3).indexOf("lo") >= 0) + "," +
        str(narrowLines.get(3).indexOf("val") >= 0) + "," +
        oneLine(narrowRendered))

    List<String> styledColumns = ["X"]
    Table styledTable = new Table(styledColumns)
    List<String> styledRow = [Ansi.fg(Color.red(), "ok")]
    styledTable.addRow(styledRow)
    String styledRendered = styledTable.render()
    print("table-style=" + str(styledRendered.indexOf("\x1b[31m") >= 0) + "," +
        str(styledRendered.indexOf("ok") >= 0) + "," +
        str(styledRendered.indexOf("| ") >= 0))

    List<String> clearColumns = ["A"]
    Table clearing = new Table(clearColumns)
    List<String> clearRow = ["x"]
    clearing.addRow(clearRow)
    clearing.clear()
    print("table-clear=" + str(clearing.rowCount()) + "," +
        str(clearing.render().indexOf("| x |") < 0))
    return 0
}
