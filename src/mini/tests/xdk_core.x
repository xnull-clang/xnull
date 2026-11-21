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
    List<String> sorted = sortBy(names, (String a, String b) -> a < b)
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

    // fs + sys: write, read back, existence
    String path = "/tmp/xnull_xdk_core.txt"
    print(writeText(path, "core"))
    print(exists(path))
    print(readText(path))
    print(fileExists(path))
    return 0
}
