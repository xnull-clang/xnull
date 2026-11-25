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

class MemoryReader implements Reader {
    List<String> lines
    Int index

    MemoryReader(List<String> lines) {
        self.lines = lines.copy()
        self.index = 0
    }

    Result<String?, Error> readLine(Context context) {
        if self.index >= self.lines.length() { return Ok(null) }
        String line = self.lines.get(self.index)
        self.index = self.index + 1
        return Ok(line)
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

    MemoryWriter barWriter = new MemoryWriter()
    Terminal barTerminal = new Terminal(context, barWriter, false, 0, 0)
    ProgressBar bar = new ProgressBar(barTerminal, 10)
    String barZero = bar.render()
    Result<Unit, Error> barSet = bar.set(5)
    String barHalf = bar.render()
    Result<Unit, Error> barMessage = bar.message("working")
    String barMessageText = bar.render()
    Result<Unit, Error> barFinish = bar.finish()
    Result<Unit, Error> barFinishAgain = bar.finish()
    print("progress-plain=" + barZero + "," + barHalf + "," + barMessageText + "," +
        str(barSet.isOk()) + "," + str(barMessage.isOk()) + "," + str(bar.value()) +
        "," + str(bar.isFinished()) + "," + str(barFinish.isOk()) + "," +
        str(barFinishAgain.isOk()) + "," + str(barWriter.data.length() > 0))
    bar.set(20)
    print("progress-clamp=" + str(bar.value()) + "," + str(bar.isFinished()))
    bar.set(0)
    bar.increment()
    print("progress-increment=" + str(bar.value()))

    MemoryWriter ttyBarWriter = new MemoryWriter()
    Terminal ttyBarTerminal = new Terminal(context, ttyBarWriter, true, 20, 5)
    ProgressBar ttyBar = new ProgressBar(ttyBarTerminal, 4)
    ttyBar.set(2)
    String ttyRender = ttyBar.render()
    Result<Unit, Error> barClear = ttyBar.clear()
    String ttyBarText = ttyBarWriter.data.toString()
    print("progress-tty=" + ttyRender + "," + str(ttyRender.length() == 20) + "," +
        str(ttyBarWriter.data.get(0) == 13) + "," + str(barClear.isOk()) + "," +
        str(ttyBarText.indexOf("\r\x1b[2K") >= 0))

    MemoryWriter spinnerWriter = new MemoryWriter()
    Terminal spinnerTerminal = new Terminal(context, spinnerWriter, true, 40, 10)
    List<String> frames = ["a", "b", "c"]
    Spinner spinner = new Spinner(spinnerTerminal, frames, 50 as Long)
    Result<Unit, Error> spinnerStart = spinner.start(null)
    String frameOne = spinner.frame()
    Result<Unit, Error> spinnerTick = spinner.tick()
    String frameTwo = spinner.frame()
    Result<Unit, Error> spinnerMessage = spinner.setMessage("msg")
    String spinnerRender = spinner.render()
    Result<Unit, Error> spinnerStop = spinner.stop()
    Result<Unit, Error> spinnerStopAgain = spinner.stop()
    String spinnerWriterText = spinnerWriter.data.toString()
    print("spinner-tty=" + str(spinnerStart.isOk()) + "," + frameOne + "," +
        str(spinnerTick.isOk()) + "," + frameTwo + "," + str(spinnerMessage.isOk()) +
        "," + spinnerRender + "," + str(spinnerStop.isOk()) + "," +
        str(spinnerStopAgain.isOk()) + "," + str(spinner.isRunning()) + "," +
        str(spinner.intervalMillis()) + "," +
        str(spinnerWriterText.indexOf("\r\x1b[2K") >= 0))

    MemoryWriter plainSpinnerWriter = new MemoryWriter()
    Terminal plainSpinnerTerminal = new Terminal(context, plainSpinnerWriter, false, 0, 0)
    Spinner plainSpinner = new Spinner(plainSpinnerTerminal, frames, 10 as Long)
    plainSpinner.start(null)
    plainSpinner.tick()
    plainSpinner.setMessage("m")
    plainSpinner.stop()
    String spinnerPlainText = plainSpinnerWriter.data.toString()
    print("spinner-plain=" + oneLine(spinnerPlainText) + "," +
        str(plainSpinner.isRunning()) + "," + plainSpinner.render())

    Context spinnerCancelContext = Context.background()
    spinnerCancelContext.cancel()
    Spinner cancelSpinner = new Spinner(spinnerTerminal, frames, 10 as Long)
    cancelSpinner.start(spinnerCancelContext)
    Result<Unit, Error> cancelTick = cancelSpinner.tick()
    print("spinner-cancel=" + errorKindName(cancelTick.error().kind()) + "," +
        str(cancelSpinner.isRunning()))

    MemoryWriter promptWriter = new MemoryWriter()
    List<String> textLines = ["alice"]
    MemoryReader textReader = new MemoryReader(textLines)
    Prompt prompt = new Prompt(textReader, promptWriter)
    Result<String, Error> textAnswer = prompt.text(context, "Name")
    String promptText = promptWriter.data.toString()
    print("prompt-text=" + textAnswer.value() + "," + promptText + "," +
        str(promptWriter.flushes))

    MemoryWriter passwordWriter = new MemoryWriter()
    List<String> passwordLines = ["secret"]
    MemoryReader passwordReader = new MemoryReader(passwordLines)
    Prompt passwordPrompt = new Prompt(passwordReader, passwordWriter)
    Result<String, Error> passwordAnswer = passwordPrompt.password(context, "Pass")
    String passwordText = passwordWriter.data.toString()
    print("prompt-password=" + passwordAnswer.value() + "," +
        str(passwordText == "Pass: "))

    MemoryWriter confirmWriter = new MemoryWriter()
    List<String> confirmLines = [" YES "]
    MemoryReader confirmReader = new MemoryReader(confirmLines)
    Prompt confirmPrompt = new Prompt(confirmReader, confirmWriter)
    Result<Bool, Error> confirmed = confirmPrompt.confirm(context, "Continue")
    String confirmText = confirmWriter.data.toString()
    print("prompt-confirm=" + str(confirmed.isOk()) + "," + str(confirmed.value()) +
        "," + str(confirmText.indexOf("[y/N]: ") >= 0))

    MemoryWriter invalidConfirmWriter = new MemoryWriter()
    List<String> invalidConfirmLines = ["maybe", "n"]
    MemoryReader invalidConfirmReader = new MemoryReader(invalidConfirmLines)
    Prompt invalidConfirmPrompt = new Prompt(invalidConfirmReader, invalidConfirmWriter)
    Result<Bool, Error> invalidConfirmed = invalidConfirmPrompt.confirm(context, "Continue")
    String invalidConfirmText = invalidConfirmWriter.data.toString()
    print("prompt-confirm-invalid=" + str(invalidConfirmed.isOk()) + "," +
        str(invalidConfirmed.value()) + "," +
        str(invalidConfirmText.indexOf("Please answer yes or no.") >= 0))

    MemoryWriter selectWriter = new MemoryWriter()
    List<String> selectLines = ["2"]
    MemoryReader selectReader = new MemoryReader(selectLines)
    Prompt selectPrompt = new Prompt(selectReader, selectWriter)
    List<String> options = ["alpha", "beta"]
    Result<String, Error> selected = selectPrompt.select(context, "Pick", options)
    String selectText = selectWriter.data.toString()
    print("prompt-select=" + selected.value() + "," +
        str(selectText.indexOf("1) alpha") >= 0) + "," +
        str(selectText.indexOf("2) beta") >= 0) + "," +
        str(selectText.indexOf("Select 1-2: ") >= 0))

    MemoryWriter invalidSelectWriter = new MemoryWriter()
    List<String> invalidSelectLines = ["9", "1"]
    MemoryReader invalidSelectReader = new MemoryReader(invalidSelectLines)
    Prompt invalidSelectPrompt = new Prompt(invalidSelectReader, invalidSelectWriter)
    Result<String, Error> invalidSelected = invalidSelectPrompt.select(context, "Pick", options)
    String invalidSelectText = invalidSelectWriter.data.toString()
    print("prompt-select-invalid=" + invalidSelected.value() + "," +
        str(invalidSelectText.indexOf("Invalid selection.") >= 0))

    MemoryWriter eofWriter = new MemoryWriter()
    List<String> eofLines = []
    MemoryReader eofReader = new MemoryReader(eofLines)
    Prompt eofPrompt = new Prompt(eofReader, eofWriter)
    Result<String, Error> eofAnswer = eofPrompt.text(context, "Name")
    print("prompt-eof=" + errorKindName(eofAnswer.error().kind()))
    Context preCancelled = Context.background()
    preCancelled.cancel()
    Result<String, Error> cancelledPrompt = prompt.text(preCancelled, "Name")
    print("prompt-cancel=" + errorKindName(cancelledPrompt.error().kind()))
    Result<String, Error> nullOptions = prompt.select(context, "Pick", null)
    print("prompt-select-null=" + errorKindName(nullOptions.error().kind()))
    return 0

}
