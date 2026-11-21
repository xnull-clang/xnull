// R4 evidence B2: process stdio adapter over real fds, not memory streams.
// The runner pipes a fixed input and captures stdout/stderr separately.
import xdk.io
import xdk.bytes
import xdk.errors

static Int main() {
    StdioReader input = stdinReader()

    Result<Bytes, Error> first = input.readExact(5)
    print(first.value().toString())
    print(input.readU8())
    print(input.readBytes(4).toString())
    print(input.readU8())

    LineReader lines = new LineReader(input)
    print(lines.readLine().value())
    print(lines.readLine().value() == null)

    Result<Int, Error> eof = input.tryReadU8()
    print(eof.isErr())
    print(eof.error().kind() == ErrorKind.DataCorrupted)
    print(input.hasRemaining())
    print(input.isClosed())

    StdioWriter out = stdoutWriter()
    out.writeBytes(Bytes.fromString("OUT:hello\n"))
    out.writeU8(33)
    out.writeBytes(Bytes.fromString("\n"))
    print(out.flush().isOk())
    print(out.close().isOk())
    print(out.isClosed())
    print(out.length())

    StdioWriter err = stderrWriter()
    err.writeBytes(Bytes.fromString("ERR:redacted\n"))
    print(err.flush().isOk())
    print(err.close().isOk())
    print(err.length())
    return 0
}
