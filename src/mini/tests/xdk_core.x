// T0 core end-to-end acceptance: exercise the core layer as a user would.
// This is the anti-stub gate. Every T0-X batch must extend it, never weaken it.
import xdk.text
import xdk.collections
import xdk.math
import xdk.errors
import xdk.config
import xdk.log
import xdk.io
import xdk.bytes
import xdk.fs
import xdk.sys

static Int main() {
    // text: trim, search, parse
    String raw = "  alpha,beta,gamma  "
    String t = raw.trim()
    print(t)
    print(contains(t, "beta"))
    print(parseInt("42").value())

    // collections: list sort, map put/getOr
    List<String> names = ["gamma", "alpha", "beta"]
    List<String> sorted = sortBy(names, (String a, String b) -> compareText(a, b) < 0)
    print(sorted.length())
    print(sorted.get(0))
    Map<String, Int> counts = ["alpha": 1]
    counts.put("beta", 2)
    print(counts.length())
    print(counts.getOr("beta", 0))

    // math: checked, overflow, combinatorics
    print(addIntChecked(2, 3).value())
    print(addIntChecked(maxIntValue(), 1).isErr())
    print(permutations(5, 2).value())

    // errors: kind and report
    BasicError missing = new BasicError(ErrorKind.NotFound, "missing")
    print(missing.kind() == ErrorKind.NotFound)
    print(missing.describe())

    // config: snapshot set/getOr
    Config cfg = new Config("dev")
    cfg.set("app.port", "8080")
    print(cfg.getOr("app.port", "?"))

    // log: one visible record
    Logger app = new Logger("core", Level.Warn)
    app.warn("closure")

    // bytes + io: write then read
    Writer out = new Writer()
    out.writeU8(65)
    Bytes suffix = Bytes.fromString("BC")
    out.writeBytes(suffix)
    print(out.length())
    Reader input = new Reader(out.toBytes())
    print(input.readU8())
    print(input.remaining())

    // io T0-X: checked reads, copy semantics, composition
    print(input.tryReadU8().isOk())
    Result<Bytes, Error> exact = input.readExact(1)
    print(toHex(exact.value()))
    Writer snapshot = new Writer()
    snapshot.writeU8(1)
    Bytes earlier = snapshot.toBytes()
    snapshot.writeU8(2)
    print(toHex(earlier))
    BufferedReader buffered = new BufferedReader(new Reader(Bytes.fromString("AB")), 1)
    print(buffered.readU8())
    print(buffered.readU8())
    print(buffered.hasRemaining())
    Writer sinkTarget = new Writer()
    BufferedWriter bufferedWriter = new BufferedWriter(sinkTarget)
    bufferedWriter.writeBytes(Bytes.fromString("ok"))
    print(bufferedWriter.flush().isOk())
    print(sinkTarget.toBytes().toString())
    print(bufferedWriter.close().isOk())
    print(sinkTarget.isClosed())
    ChainReader chain = new ChainReader(new Reader(Bytes.fromString("A")), new Reader(Bytes.fromString("B")))
    print(chain.readU8())
    print(chain.readU8())
    Writer teeTarget = new Writer()
    TeeReader tee = new TeeReader(new Reader(Bytes.fromString("T")), teeTarget)
    print(tee.readU8())
    print(teeTarget.toBytes().toString())
    LimitReader limited = new LimitReader(new Reader(Bytes.fromString("XYZ")), 1)
    print(limited.readU8())
    print(limited.hasRemaining())
    LineReader lines = new LineReader(new Reader(Bytes.fromString("a\nb\n")))
    print(lines.readLine().value())
    print(lines.readLine().value())
    print(lines.readLine().value() == null)
    print(readAll(new Reader(Bytes.fromString("all"))).value().toString())
    Writer copiedSink = new Writer()
    print(copyTo(new Reader(Bytes.fromString("cp")), copiedSink).value())
    print(copiedSink.toBytes().toString())

    // fs + sys: write, read back, existence
    String path = "/tmp/xnull_xdk_core.txt"
    print(writeText(path, "core"))
    print(exists(path))
    print(readText(path))
    print(fileExists(path))
    return 0
}
