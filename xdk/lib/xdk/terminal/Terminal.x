// xdk.terminal —— ANSI 颜色/样式/终端/表格核心（M21.4）
//
// 实现 Color/Ansi/Style/Terminal/Table；ProgressBar/Spinner/Prompt 留 M21.5。
// 不探测真实 TTY/尺寸；非终端模式剥离 CSI。
package xdk.terminal
import xdk.errors
import xdk.bytes
import xdk.text

// ---------- Color ----------
class Color {
    final Int _mode
    final Int _index
    final Int _r
    final Int _g
    final Int _b

    private Color(Int mode, Int index, Int redChannel, Int greenChannel, Int blueChannel) {
        if mode < 0 || mode > 2 { throw "Color: invalid mode" }
        if mode == 0 && (index < 0 || index > 15) {
            throw "Color: basic index out of range"
        }
        if mode == 1 && (index < 0 || index > 255) {
            throw "Color: index out of range"
        }
        if mode == 2 && (redChannel < 0 || redChannel > 255 ||
            greenChannel < 0 || greenChannel > 255 ||
            blueChannel < 0 || blueChannel > 255) {
            throw "Color: RGB channel out of range"
        }
        self._mode = mode
        self._index = index
        self._r = redChannel
        self._g = greenChannel
        self._b = blueChannel
    }

    static Color basic(Int index) {
        if index < 0 || index > 15 { throw "Color.basic: index out of range" }
        return new Color(0, index, 0, 0, 0)
    }

    static Color black() { return Color.basic(0) }
    static Color red() { return Color.basic(1) }
    static Color green() { return Color.basic(2) }
    static Color yellow() { return Color.basic(3) }
    static Color blue() { return Color.basic(4) }
    static Color magenta() { return Color.basic(5) }
    static Color cyan() { return Color.basic(6) }
    static Color white() { return Color.basic(7) }
    static Color brightBlack() { return Color.basic(8) }
    static Color brightRed() { return Color.basic(9) }
    static Color brightGreen() { return Color.basic(10) }
    static Color brightYellow() { return Color.basic(11) }
    static Color brightBlue() { return Color.basic(12) }
    static Color brightMagenta() { return Color.basic(13) }
    static Color brightCyan() { return Color.basic(14) }
    static Color brightWhite() { return Color.basic(15) }

    static Color indexed(Int index) {
        if index < 0 || index > 255 { throw "Color.indexed: index out of range" }
        return new Color(1, index, 0, 0, 0)
    }

    static Color rgb(Int redChannel, Int greenChannel, Int blueChannel) {
        if redChannel < 0 || redChannel > 255 || greenChannel < 0 ||
            greenChannel > 255 || blueChannel < 0 || blueChannel > 255 {
            throw "Color.rgb: channel out of range"
        }
        return new Color(2, 0, redChannel, greenChannel, blueChannel)
    }

    Int mode() { return self._mode }
    Bool isBasic() { return self._mode == 0 }
    Bool isIndexed() { return self._mode == 1 }
    Bool isRgb() { return self._mode == 2 }

    Int basicIndex() {
        if self._mode != 0 { throw "Color.basicIndex: not basic" }
        return self._index
    }

    Int index() {
        if self._mode != 1 { throw "Color.index: not indexed" }
        return self._index
    }

    Int redChannel() {
        if self._mode != 2 { throw "Color.redChannel: not rgb" }
        return self._r
    }

    Int greenChannel() {
        if self._mode != 2 { throw "Color.greenChannel: not rgb" }
        return self._g
    }

    Int blueChannel() {
        if self._mode != 2 { throw "Color.blueChannel: not rgb" }
        return self._b
    }

    Bool equals(Color other) {
        if other == null { return false }
        if self._mode != other.mode() { return false }
        if self._mode == 2 {
            return self._r == other.redChannel() &&
                self._g == other.greenChannel() &&
                self._b == other.blueChannel()
        }
        return self._index == other._index
    }

    String describe() {
        if self._mode == 0 { return "basic(" + str(self._index) + ")" }
        if self._mode == 1 { return "indexed(" + str(self._index) + ")" }
        return "rgb(" + str(self._r) + "," + str(self._g) + "," + str(self._b) + ")"
    }

    String toString() { return self.describe() }
}

// ---------- Ansi ----------
class Ansi {
    private Ansi() { }

    private static String esc() { return "\x1b[" }

    private static String wrap(String code, String text) {
        return Ansi.esc() + code + text + Ansi.esc() + "0m"
    }

    static String reset() { return Ansi.esc() + "0m" }

    static String bold(String text) {
        if text == null { throw "Ansi.bold: null text" }
        return Ansi.wrap("1m", text)
    }

    static String dim(String text) {
        if text == null { throw "Ansi.dim: null text" }
        return Ansi.wrap("2m", text)
    }

    static String italic(String text) {
        if text == null { throw "Ansi.italic: null text" }
        return Ansi.wrap("3m", text)
    }

    static String underline(String text) {
        if text == null { throw "Ansi.underline: null text" }
        return Ansi.wrap("4m", text)
    }

    static String fg(Color color, String text) {
        if color == null || text == null { throw "Ansi.fg: null argument" }
        if color.isBasic() {
            Int index = color.basicIndex()
            if index < 8 { return Ansi.wrap(str(30 + index) + "m", text) }
            return Ansi.wrap(str(90 + index - 8) + "m", text)
        }
        if color.isIndexed() { return Ansi.color256(color.index(), text) }
        return Ansi.rgb(color.redChannel(), color.greenChannel(), color.blueChannel(), text)
    }

    static String bg(Color color, String text) {
        if color == null || text == null { throw "Ansi.bg: null argument" }
        if color.isBasic() {
            Int index = color.basicIndex()
            if index < 8 { return Ansi.wrap(str(40 + index) + "m", text) }
            return Ansi.wrap(str(100 + index - 8) + "m", text)
        }
        if color.isIndexed() {
            return Ansi.wrap("48;5;" + str(color.index()) + "m", text)
        }
        return Ansi.wrap("48;2;" + str(color.redChannel()) + ";" +
            str(color.greenChannel()) + ";" + str(color.blueChannel()) + "m", text)
    }

    static String color256(Int index, String text) {
        if text == null { throw "Ansi.color256: null text" }
        if index < 0 || index > 255 { throw "Ansi.color256: index out of range" }
        return Ansi.wrap("38;5;" + str(index) + "m", text)
    }

    static String rgb(Int redChannel, Int greenChannel, Int blueChannel, String text) {
        if text == null { throw "Ansi.rgb: null text" }
        if redChannel < 0 || redChannel > 255 || greenChannel < 0 ||
            greenChannel > 255 || blueChannel < 0 || blueChannel > 255 {
            throw "Ansi.rgb: channel out of range"
        }
        return Ansi.wrap("38;2;" + str(redChannel) + ";" + str(greenChannel) +
            ";" + str(blueChannel) + "m", text)
    }

    static String cursorUp(Int rows) {
        if rows < 1 { throw "Ansi.cursorUp: rows < 1" }
        return Ansi.esc() + str(rows) + "A"
    }

    static String cursorDown(Int rows) {
        if rows < 1 { throw "Ansi.cursorDown: rows < 1" }
        return Ansi.esc() + str(rows) + "B"
    }

    static String clearScreen() { return Ansi.esc() + "2J" + Ansi.esc() + "H" }
    static String hideCursor() { return Ansi.esc() + "?25l" }
    static String showCursor() { return Ansi.esc() + "?25h" }
}

// ---------- Style ----------
class Style {
    final Color? _fg
    final Color? _bg
    final Bool _bold
    final Bool _italic
    final Bool _underline

    Style() {
        self._fg = null
        self._bg = null
        self._bold = false
        self._italic = false
        self._underline = false
    }

    private Style(Color? fg, Color? bg, Bool bold, Bool italic, Bool underline) {
        self._fg = fg
        self._bg = bg
        self._bold = bold
        self._italic = italic
        self._underline = underline
    }

    Style fg(Color color) {
        if color == null { throw "Style.fg: null color" }
        return new Style(color, self._bg, self._bold, self._italic, self._underline)
    }

    Style bg(Color color) {
        if color == null { throw "Style.bg: null color" }
        return new Style(self._fg, color, self._bold, self._italic, self._underline)
    }

    Style boldOn() {
        return new Style(self._fg, self._bg, true, self._italic, self._underline)
    }

    Style italicOn() {
        return new Style(self._fg, self._bg, self._bold, true, self._underline)
    }

    Style underlineOn() {
        return new Style(self._fg, self._bg, self._bold, self._italic, true)
    }

    String render(String text) {
        if text == null { throw "Style.render: null text" }
        String result = text
        if self._underline { result = Ansi.underline(result) }
        if self._italic { result = Ansi.italic(result) }
        if self._bold { result = Ansi.bold(result) }
        if self._bg != null {
            Color background = self._bg as Color
            result = Ansi.bg(background, result)
        }
        if self._fg != null {
            Color foreground = self._fg as Color
            result = Ansi.fg(foreground, result)
        }
        return result
    }

    String apply(String text) { return self.render(text) }

    Bool isPlain() {
        return self._fg == null && self._bg == null && !self._bold &&
            !self._italic && !self._underline
    }

    Style copy() {
        return new Style(self._fg, self._bg, self._bold, self._italic, self._underline)
    }

    Bool equals(Style other) {
        if other == null { return false }
        if self._bold != other.isBold() || self._italic != other.isItalic() ||
            self._underline != other.isUnderline() { return false }
        if self._fg == null {
            if other.foreground() != null { return false }
        } else {
            Color fgValue = self._fg as Color
            Color? otherFg = other.foreground()
            if otherFg == null { return false }
            if !fgValue.equals(otherFg as Color) { return false }
        }
        if self._bg == null {
            if other.background() != null { return false }
        } else {
            Color bgValue = self._bg as Color
            Color? otherBg = other.background()
            if otherBg == null { return false }
            if !bgValue.equals(otherBg as Color) { return false }
        }
        return true
    }

    Color? foreground() { return self._fg }
    Color? background() { return self._bg }
    Bool isBold() { return self._bold }
    Bool isItalic() { return self._italic }
    Bool isUnderline() { return self._underline }
}

// ---------- Terminal ----------
protocol Writer {
    Bool isOpen();
    Result<Unit, Error> writeAll(Context context, Bytes data);
    Result<Unit, Error> flush();
}

class Terminal {
    final Context _context
    final Writer _writer
    final Bool _isTerminal
    final Int _width
    final Int _height
    Bool _closed

    Terminal(Context context, Writer writer, Bool isTerminal, Int width, Int height) {
        if context == null || writer == null { throw "Terminal: null context/writer" }
        if width < 0 || height < 0 { throw "Terminal: negative dimension" }
        self._context = context
        self._writer = writer
        self._isTerminal = isTerminal
        self._width = width
        self._height = height
        self._closed = false
    }

    Bool isTerminal() { return self._isTerminal }
    Int width() { return self._width }
    Int height() { return self._height }
    Bool isClosed() { return self._closed }

    Result<Unit, Error> write(String text) {
        if text == null { throw "Terminal.write: null text" }
        if self._closed || !self._writer.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "terminal writer is closed"))
        }
        String output = text
        if !self._isTerminal { output = terminalPlain(text) }
        return self._writer.writeAll(self._context, fromUtf8(output))
    }

    Result<Unit, Error> writeLine(String text) {
        if text == null { throw "Terminal.writeLine: null text" }
        return self.write(text + "\n")
    }

    Result<Unit, Error> clear() {
        if !self._isTerminal { return Ok() }
        return self.write(Ansi.clearScreen())
    }

    Result<Unit, Error> refresh() { return self.clear() }

    Result<Unit, Error> flush() {
        if self._closed {
            return Err(new BasicError(ErrorKind.Unavailable, "terminal writer is closed"))
        }
        return self._writer.flush()
    }

    Result<Unit, Error> close() {
        self._closed = true
        return Ok()
    }
}

// ---------- Table ----------
class Table {
    final List<String> _columns
    final List<List<String>> _rows
    final Int _maxWidth

    Table(List<String> columns) {
        if columns == null { throw "Table: null columns" }
        self._columns = columns.copy()
        self._rows = []
        self._maxWidth = 0
    }

    Table(List<String> columns, Int maxWidth) {
        if columns == null { throw "Table: null columns" }
        if maxWidth < 0 { throw "Table: negative maxWidth" }
        self._columns = columns.copy()
        self._rows = []
        self._maxWidth = maxWidth
    }

    Void addRow(List<String> cells) {
        if cells == null { throw "Table.addRow: null cells" }
        if cells.length() != self._columns.length() {
            throw "Table.addRow: cell count does not match columns"
        }
        List<String> copied = []
        Int index = 0
        while index < cells.length() {
            String cell = cells.get(index)
            if cell == null { throw "Table.addRow: null cell" }
            if cell.indexOf("\n") >= 0 || cell.indexOf("\r") >= 0 {
                throw "Table.addRow: newline in cell"
            }
            copied.push(cell)
            index = index + 1
        }
        self._rows.push(copied)
    }

    Void clear() { self._rows.clear() }
    List<String> columns() { return self._columns.copy() }
    Int rowCount() { return self._rows.length() }
    Int maxWidth() { return self._maxWidth }

    String render() {
        List<Int> widths = []
        Int columnIndex = 0
        while columnIndex < self._columns.length() {
            Int width = terminalVisibleWidth(self._columns.get(columnIndex))
            Int rowIndex = 0
            while rowIndex < self._rows.length() {
                Int cellWidth = terminalVisibleWidth(self._rows.get(rowIndex).get(columnIndex))
                if cellWidth > width { width = cellWidth }
                rowIndex = rowIndex + 1
            }
            widths.push(width)
            columnIndex = columnIndex + 1
        }
        if self._maxWidth > 0 {
            while self.tableWidth(widths) > self._maxWidth {
                Int widest = widths.get(0)
                Int widestIndex = 0
                Int index = 1
                while index < widths.length() {
                    if widths.get(index) > widest {
                        widest = widths.get(index)
                        widestIndex = index
                    }
                    index = index + 1
                }
                if widest <= 1 { break }
                widths.set(widestIndex, widest - 1)
            }
        }
        String result = self.renderBorder(widths)
        result = result + "\n" + self.renderRow(self._columns, widths)
        result = result + "\n" + self.renderBorder(widths)
        Int rowIndex = 0
        while rowIndex < self._rows.length() {
            result = result + "\n" + self.renderRow(self._rows.get(rowIndex), widths)
            rowIndex = rowIndex + 1
        }
        if self._rows.length() > 0 {
            result = result + "\n" + self.renderBorder(widths)
        }
        return result
    }

    private Int tableWidth(List<Int> widths) {
        Int total = 1
        Int index = 0
        while index < widths.length() {
            total = total + widths.get(index) + 3
            index = index + 1
        }
        return total
    }

    private String renderBorder(List<Int> widths) {
        String result = "+"
        Int index = 0
        while index < widths.length() {
            result = result + terminalRepeat("-", widths.get(index) + 2) + "+"
            index = index + 1
        }
        return result
    }

    private String renderRow(List<String> cells, List<Int> widths) {
        String result = "|"
        Int index = 0
        while index < cells.length() {
            String cell = cells.get(index)
            Int width = widths.get(index)
            Int visible = terminalVisibleWidth(cell)
            String rendered = cell
            if visible > width {
                rendered = terminalTruncate(cell, width)
                visible = width
            }
            result = result + " " + rendered +
                terminalRepeat(" ", width - visible) + " |"
            index = index + 1
        }
        return result
    }
}

// ---------- 内部文本辅助 ----------
static String terminalPlain(String text) {
    String result = ""
    Int index = 0
    while index < text.length() {
        Int code = text.get(index)
        if code == 27 && index + 1 < text.length() && text.get(index + 1) == 91 {
            index = terminalAnsiEnd(text, index)
        } else {
            result = result + text.substring(index, 1)
            index = index + 1
        }
    }
    return result
}

static Int terminalAnsiEnd(String text, Int start) {
    Int index = start + 2
    while index < text.length() {
        Int code = text.get(index)
        index = index + 1
        if code >= 64 && code <= 126 { return index }
    }
    return index
}

static Int terminalVisibleWidth(String text) {
    return terminalPlain(text).length()
}

static String terminalTruncate(String text, Int width) {
    String plain = terminalPlain(text)
    if width >= plain.length() { return plain }
    if width <= 0 { return "" }
    return plain.substring(0, width)
}

static String terminalRepeat(String text, Int count) {
    String result = ""
    Int index = 0
    while index < count {
        result = result + text
        index = index + 1
    }
    return result
}

// ---------- Reader（Prompt 行读取） ----------
protocol Reader {
    Result<String?, Error> readLine(Context context);
}

// ---------- ProgressBar ----------
class ProgressBar {
    final Terminal _terminal
    final Int _total
    Int _value
    String _message
    Bool _finished
    Int _lastWidth

    ProgressBar(Terminal terminal, Int total) {
        if terminal == null { throw "ProgressBar: null terminal" }
        if total < 1 { throw "ProgressBar: total must be positive" }
        self._terminal = terminal
        self._total = total
        self._value = 0
        self._message = ""
        self._finished = false
        self._lastWidth = 0
    }

    Int total() { return self._total }
    Int value() { return self._value }
    Bool isFinished() { return self._finished }

    Result<Unit, Error> set(Int value) {
        Int next = value
        if next < 0 { next = 0 }
        if next > self._total { next = self._total }
        self._value = next
        self._finished = false
        if !self._terminal.isTerminal() { return Ok() }
        return self.draw(false)
    }

    Result<Unit, Error> increment() {
        if self._value >= self._total { return Ok() }
        return self.set(self._value + 1)
    }

    Result<Unit, Error> message(String text) {
        if text == null { throw "ProgressBar.message: null text" }
        self._message = text
        if !self._terminal.isTerminal() { return Ok() }
        return self.draw(false)
    }

    Result<Unit, Error> finish() {
        if self._finished { return Ok() }
        self._value = self._total
        self._finished = true
        if self._terminal.isTerminal() { return self.draw(true) }
        Result<Unit, Error> written = self._terminal.writeLine(self.render())
        if written.isErr() { return written }
        return self._terminal.flush()
    }

    Result<Unit, Error> clear() {
        if !self._terminal.isTerminal() { return Ok() }
        self._lastWidth = 0
        Result<Unit, Error> written = self._terminal.write("\r\x1b[2K")
        if written.isErr() { return written }
        return self._terminal.flush()
    }

    String render() {
        Int percent = (self._value * 100) / self._total
        String percentText = str(percent) + "%"
        if !self._terminal.isTerminal() {
            String text = percentText + " " + str(self._value) + "/" + str(self._total)
            if self._message != "" { text = text + " " + self._message }
            return text
        }
        Int width = self._terminal.width()
        if width <= 0 { width = 40 }
        String message = self._message
        Int fixed = 2 + 1 + percentText.length()
        Int barWidth = width - fixed
        if message != "" { barWidth = barWidth - message.length() - 1 }
        if barWidth < 1 {
            message = ""
            barWidth = width - fixed
        }
        if barWidth < 1 { return percentText }
        Int filled = (self._value * barWidth) / self._total
        if filled > barWidth { filled = barWidth }
        String bar = ""
        Int index = 0
        while index < barWidth {
            if index < filled { bar = bar + "#" } else { bar = bar + "-" }
            index = index + 1
        }
        String line = "[" + bar + "] " + percentText
        if message != "" { line = line + " " + message }
        if line.length() > width { line = line.substring(0, width) }
        return line
    }

    private Result<Unit, Error> draw(Bool newline) {
        if !self._terminal.isTerminal() { return Ok() }
        String line = self.render()
        String output = "\r" + line
        if line.length() < self._lastWidth {
            output = output + terminalRepeat(" ", self._lastWidth - line.length())
        }
        if newline {
            output = output + "\n"
            self._lastWidth = 0
        } else {
            self._lastWidth = line.length()
        }
        Result<Unit, Error> written = self._terminal.write(output)
        if written.isErr() { return written }
        return self._terminal.flush()
    }
}

// ---------- Spinner ----------
class Spinner {
    final Terminal _terminal
    final List<String> _frames
    final Long _intervalMillis
    Int _frameIndex
    String _message
    Bool _running
    Context? _context
    Int _lastWidth

    Spinner(Terminal terminal, List<String> frames, Long intervalMillis) {
        if terminal == null { throw "Spinner: null terminal" }
        if frames == null || frames.length() == 0 { throw "Spinner: empty frames" }
        if intervalMillis < 1 as Long { throw "Spinner: interval must be positive" }
        Int index = 0
        while index < frames.length() {
            if frames.get(index) == null { throw "Spinner: null frame" }
            index = index + 1
        }
        self._terminal = terminal
        self._frames = frames.copy()
        self._intervalMillis = intervalMillis
        self._frameIndex = 0
        self._message = ""
        self._running = false
        self._context = null
        self._lastWidth = 0
    }

    Result<Unit, Error> start(Context? context) {
        if self._running {
            self._context = context
            return Ok()
        }
        self._running = true
        self._frameIndex = 0
        self._context = context
        return self.draw()
    }

    Result<Unit, Error> tick() {
        if !self._running { return Ok() }
        if self._context != null {
            Context context = self._context as Context
            if context.isCancelled() {
                Result<Unit, Error> cleared = self.clearLine()
                self._running = false
                self._context = null
                if cleared.isErr() { return cleared }
                return Err(new BasicError(ErrorKind.Cancelled, "spinner tick"))
            }
        }
        self._frameIndex = (self._frameIndex + 1) % self._frames.length()
        return self.draw()
    }

    Result<Unit, Error> stop() {
        if !self._running { return Ok() }
        self._running = false
        self._context = null
        return self.clearLine()
    }

    Result<Unit, Error> setMessage(String text) {
        if text == null { throw "Spinner.setMessage: null text" }
        self._message = text
        if !self._running { return Ok() }
        return self.draw()
    }

    Bool isRunning() { return self._running }
    String frame() { return self._frames.get(self._frameIndex) }
    Long intervalMillis() { return self._intervalMillis }

    String render() {
        if self._message == "" { return self.frame() }
        return self.frame() + " " + self._message
    }

    private Result<Unit, Error> draw() {
        String line = self.render()
        if !self._terminal.isTerminal() {
            Result<Unit, Error> written = self._terminal.writeLine(line)
            if written.isErr() { return written }
            return self._terminal.flush()
        }
        String output = "\r" + line
        if line.length() < self._lastWidth {
            output = output + terminalRepeat(" ", self._lastWidth - line.length())
        }
        self._lastWidth = line.length()
        Result<Unit, Error> written = self._terminal.write(output)
        if written.isErr() { return written }
        return self._terminal.flush()
    }

    private Result<Unit, Error> clearLine() {
        if !self._terminal.isTerminal() { return Ok() }
        self._lastWidth = 0
        Result<Unit, Error> written = self._terminal.write("\r\x1b[2K")
        if written.isErr() { return written }
        return self._terminal.flush()
    }
}

// ---------- Prompt ----------
class Prompt {
    final Reader _reader
    final Writer _writer

    Prompt(Reader reader, Writer writer) {
        if reader == null || writer == null {
            throw "Prompt: null reader or writer"
        }
        self._reader = reader
        self._writer = writer
    }

    Result<String, Error> text(Context context, String message) {
        if context == null { throw "Prompt.text: null context" }
        if message == null { throw "Prompt.text: null message" }
        Result<Unit, Error> written = self.writeText(context, message + ": ")
        if written.isErr() { return Err(written.error()) }
        return self.readAnswer(context, "prompt.text")
    }

    Result<String, Error> password(Context context, String message) {
        if context == null { throw "Prompt.password: null context" }
        if message == null { throw "Prompt.password: null message" }
        Result<Unit, Error> written = self.writeText(context, message + ": ")
        if written.isErr() { return Err(written.error()) }
        return self.readAnswer(context, "prompt.password")
    }

    Result<Bool, Error> confirm(Context context, String message) {
        if context == null { throw "Prompt.confirm: null context" }
        if message == null { throw "Prompt.confirm: null message" }
        Int attempts = 0
        while attempts < 8 {
            attempts = attempts + 1
            Result<Unit, Error> written = self.writeText(context, message + " [y/N]: ")
            if written.isErr() { return Err(written.error()) }
            Result<String, Error> answer = self.readAnswer(context, "prompt.confirm")
            if answer.isErr() { return Err(answer.error()) }
            String normalized = answer.value().trim().toLower()
            if normalized == "" || normalized == "n" || normalized == "no" {
                return Ok(false)
            }
            if normalized == "y" || normalized == "yes" {
                return Ok(true)
            }
            Result<Unit, Error> invalid = self.writeText(context, "Please answer yes or no.\n")
            if invalid.isErr() { return Err(invalid.error()) }
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "prompt.confirm: too many invalid answers"))
    }

    Result<String, Error> select(Context context, String message, List<String> options) {
        if context == null { throw "Prompt.select: null context" }
        if message == null { throw "Prompt.select: null message" }
        if options == null || options.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "prompt.select: empty options"))
        }
        Int index = 0
        while index < options.length() {
            if options.get(index) == null {
                return Err(new BasicError(ErrorKind.InvalidArgument, "prompt.select: null option"))
            }
            index = index + 1
        }
        Int attempts = 0
        while attempts < 8 {
            attempts = attempts + 1
            String menu = message + "\n"
            index = 0
            while index < options.length() {
                menu = menu + "  " + str(index + 1) + ") " + options.get(index) + "\n"
                index = index + 1
            }
            menu = menu + "Select 1-" + str(options.length()) + ": "
            Result<Unit, Error> written = self.writeText(context, menu)
            if written.isErr() { return Err(written.error()) }
            Result<String, Error> answer = self.readAnswer(context, "prompt.select")
            if answer.isErr() { return Err(answer.error()) }
            Result<Int, Error> parsed = parseInt(answer.value().trim())
            if parsed.isErr() {
                Result<Unit, Error> invalid = self.writeText(context, "Invalid selection.\n")
                if invalid.isErr() { return Err(invalid.error()) }
            } else {
                Int picked = parsed.value()
                if picked >= 1 && picked <= options.length() {
                    return Ok(options.get(picked - 1))
                }
                Result<Unit, Error> invalid = self.writeText(context, "Invalid selection.\n")
                if invalid.isErr() { return Err(invalid.error()) }
            }
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "prompt.select: too many invalid answers"))
    }

    private Result<String, Error> readAnswer(Context context, String label) {
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, label))
        }
        Result<String?, Error> line = self._reader.readLine(context)
        if line.isErr() { return Err(line.error()) }
        String? value = line.value()
        if value == null {
            return Err(new BasicError(ErrorKind.Io, label + ": end of input"))
        }
        return Ok(value as String)
    }

    private Result<Unit, Error> writeText(Context context, String text) {
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "prompt write"))
        }
        Result<Unit, Error> written = self._writer.writeAll(context, fromUtf8(text))
        if written.isErr() { return written }
        return self._writer.flush()
    }
}
