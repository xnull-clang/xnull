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
import xdk.cli

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

    // collections T0-X: joinWith, grouping, generic entries, ordered maps, Set<T>
    List<Int> marks = [5, 2, 7, 4, 9]
    List<Int> noMarks = []
    print(joinWith<Int>(marks, "-", (Int value) -> str(value)))
    Map<Int, List<Int>> buckets = groupByInt<Int>(marks, (Int value) -> value % 2)
    print(buckets.length())
    print(buckets.getOr(0, noMarks).length())
    print(buckets.getOr(1, noMarks).get(0))
    List<Entry<Int, List<Int>>> bucketEntries = buckets.entries()
    print(bucketEntries.length())
    print(bucketEntries.get(0).key)
    print(bucketEntries.get(0).value.length())
    Map<String, List<Int>> byBand = groupBy<Int, String>(marks, (Int value) -> str(value % 2))
    print(byBand.getOr("1", noMarks).length())
    Map<String, Long> totals = [:]
    totals.put("alpha", 10)
    totals.put("beta", 20)
    List<Entry<String, Long>> totalEntries = totals.entries()
    print(totalEntries.length())
    print(totalEntries.get(0).key)
    print(totalEntries.get(0).value)
    OrderedMap<String> ordered = new OrderedMap<String>()
    print(ordered.put(2, "two") == null)
    ordered.put(1, "one")
    print(ordered.put(2, "TWO"))
    print(ordered.getOr(1, "?"))
    print(ordered.keys().get(0))
    BTreeMap<String> tree = new BTreeMap<String>()
    tree.put(5, "five")
    tree.put(1, "one")
    tree.put(3, "three")
    print(tree.keys().get(0))
    print(tree.keys().get(2))
    print(tree.getOr(3, "?"))
    print(tree.remove(5))
    Set<Long> large = Set.of(9000000000, 4, 4)
    print(large.length())
    print(large.add(5))
    print(large.has(4))

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

    // fs + sys: write, read back, existence (T0-X Result surface)
    String path = "/tmp/xnull_xdk_core.txt"
    print(writeText(path, "core").value())
    print(exists(path))
    print(readText(path).value())
    print(fileExists(path))

    // fs T0-X: File/Dir/Path, Long offset, atomic/temp/walk/glob,
    // metadata, permissions, and links.
    String fsRoot = "/tmp/xnull_xdk_core_fs"
    Result<Unit, Error> fsCleaned = removeDirAll(fsRoot)
    print(makeDir(fsRoot).isOk())
    print(writeText(fsRoot + "/a.txt", "core-fs").value())
    Path corePath = new Path(fsRoot + "/a.txt")
    print(corePath.name())
    print(corePath.extension())
    print(corePath.isAbsolute())
    File coreFile = openFileRead(fsRoot + "/a.txt").value()
    print(coreFile.size().value())
    print(coreFile.seek(5 as Long).isOk())
    print(coreFile.read(2 as Long).value().toString())
    print(coreFile.close().isOk())
    print(writeTextAtomic(fsRoot + "/atomic.txt", "ok").value())
    print(readText(fsRoot + "/atomic.txt").value())
    print(metadata(fsRoot + "/a.txt").value().isFile())
    print(metadata(fsRoot + "/a.txt").value().size)
    print(setPermissions(fsRoot + "/a.txt", 384).isOk())
    print(permissions(fsRoot + "/a.txt").value())
    print(createSymlink(fsRoot + "/a.txt", fsRoot + "/link.txt").isOk())
    print(readLink(fsRoot + "/link.txt").value() == fsRoot + "/a.txt")
    print(linkMetadata(fsRoot + "/link.txt").value().isSymlink())
    print(removeFile(fsRoot + "/link.txt").isOk())
    print(makeDir(fsRoot + "/sub").isOk())
    print(writeText(fsRoot + "/sub/b.txt", "bb").value())
    print(walk(fsRoot).value().length())
    print(glob(fsRoot + "/**/*.txt").value().length())
    Dir coreDir = openDir(fsRoot + "/sub").value()
    print(coreDir.next().value())
    print(coreDir.next().value() == null)
    print(coreDir.close().isOk())
    TempFile coreTemp = createTempFile("").value()
    print(exists(coreTemp.path))
    print(coreTemp.close().isOk())
    print(exists(coreTemp.path))
    TempDir coreTempDir = createTempDir("").value()
    print(isDir(coreTempDir.path))
    print(coreTempDir.close().isOk())
    print(exists(coreTempDir.path))
    print(copyFile(fsRoot + "/a.txt", fsRoot + "/copy.txt").isOk())
    print(renameFile(fsRoot + "/copy.txt", fsRoot + "/moved.txt").isOk())
    print(exists(fsRoot + "/moved.txt"))
    print(removeDirAll(fsRoot).isOk())
    print(exists(fsRoot))

    // sys T0-X: Result top-level, env/platform, stdio pipes, signals/groups,
    // and the embedded-resource read subset.
    String sysPath = "/tmp/xnull_xdk_core_sys.txt"
    print(writeFileText(sysPath, "核心").value())
    print(readFileText(sysPath).value())
    print(readFileText("/tmp/xnull_xdk_core_sys_missing.txt").isErr())
    print(readFileText("/tmp/xnull_xdk_core_sys_missing.txt").error().kind() == ErrorKind.NotFound)
    print(envHas("XDK_CORE_PROBE"))
    print(env("XDK_CORE_PROBE"))
    Bool probeSeen = false
    List<String> sysEnv = envNames()
    Int sysEnvIndex = 0
    while sysEnvIndex < sysEnv.length() {
        if sysEnv.get(sysEnvIndex) == "XDK_CORE_PROBE" {
            probeSeen = true
        }
        sysEnvIndex = sysEnvIndex + 1
    }
    print(probeSeen)
    print(platform().length() > 0)
    print(cwd().length() > 0)
    print(pid() > 0)
    print(fileMtime(sysPath) >= 0)
    Result<Process, Error> pipeOpened = spawnProcessPiped("cat")
    Process pipeProcess = pipeOpened.value()
    print(pipeProcess.isPiped())
    print(pipeProcess.writeStdinText("pipe").value())
    print(pipeProcess.closeStdin().isOk())
    print(pipeProcess.readStdoutText().value())
    print(pipeProcess.wait().value())
    print(pipeProcess.close().isOk())
    Result<Process, Error> groupOpened = spawnProcessPiped("sleep 30")
    Process groupProcess = groupOpened.value()
    print(groupProcess.sendGroupSignal(Signal.Terminate).isOk())
    print(groupProcess.wait().value())
    print(groupProcess.close().isOk())
    print(signalNumber(Signal.Kill) > 0)
    print(resourceExists("missing.txt"))
    print(resourceCount())
    print(readResourceText(null, "missing.txt").isErr())
    print(readResourceText(null, "missing.txt").error().kind() == ErrorKind.NotFound)
    print(listResources(null, "").value().length())

    // text T0-X: Unicode, POSIX ERE subset, printf Format
    print(codePointAt("é", 0))
    print(codePointCount("éA"))
    print(regexCompile("^(ab)+c{2,3}$").value().isMatch("abcc"))
    List<Match> coreMatches = regexCompile("(a+)(b+)").value().findAll("xxaaabb")
    print(coreMatches.length())
    print(coreMatches.get(0).group(2))
    List<FormatArgument> coreFormatArgs = []
    coreFormatArgs.push(FormatArgument.ofInt(7))
    coreFormatArgs.push(FormatArgument.ofText("ok"))
    print(printf("%04d:%s", coreFormatArgs).value())
    Result<Utf16, Error> repairedCore = utf8ToUtf16(fromHex("ff"))
    print(repairedCore.value().get(0) as Int)

    // log T0-X: structured fields and a pluggable sink.
    MemorySink coreSink = new MemorySink()
    Logger coreBase = new Logger("core", Level.Info)
    Logger coreSinkLogger = coreBase.withSink(coreSink)
    Logger coreFieldLogger = coreSinkLogger.withField("k", "v")
    coreFieldLogger.info("sink")
    List<String> coreLines = coreSink.lines()
    print(coreLines.length())
    print(coreLines.get(0))

    // config T0-X: source apply and overlay.
    List<ConfigEntry> coreEntries = []
    coreEntries.push(new ConfigEntry("feature", "on"))
    MapSource coreSource = new MapSource(coreEntries)
    Config coreConfig = new Config("core")
    Result<Unit, Error> coreApplied = coreConfig.apply(coreSource)
    print(coreApplied.isOk())
    print(coreConfig.getOr("feature", "off"))
    Config coreOverlay = new Config("override")
    coreOverlay.set("feature", "override")
    Config coreMerged = coreConfig.overlay(coreOverlay)
    print(coreMerged.getOr("feature", "off"))

    // cli T0-X: option spec, command parse, and help.
    List<OptionSpec> coreOptions = []
    coreOptions.push(new OptionSpec("--flag", false, "flag", false))
    Command coreCommand = new Command("core", "core command", coreOptions)
    List<String> coreArgv = ["--flag"]
    Args coreArgs = new Args(coreArgv)
    Result<CommandMatch, Error> coreMatch = coreCommand.parse(coreArgs)
    print(coreMatch.isOk())
    print(coreCommand.help())
    return 0
}
