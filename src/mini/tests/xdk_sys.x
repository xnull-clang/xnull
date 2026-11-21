import xdk.sys
import xdk.errors

static Int main() {
    // Result file surface: UTF-8 byte count, readback, missing classification.
    String path = "/tmp/xnull_xdk_sys_probe.txt"
    Result<Long, Error> written = writeFileText(path, "hé")
    print(written.value())
    print(readFileText(path).value())
    print(fileExists(path))
    Result<String, Error> missing = readFileText("/tmp/xnull_xdk_sys_missing.txt")
    print(missing.isErr())
    print(missing.error().kind() == ErrorKind.NotFound)

    // Environment enumeration and stable projection.
    print(envHas("XDK_SYS_PROBE"))
    print(env("XDK_SYS_PROBE"))
    Bool seen = false
    List<String> names = envNames()
    Int i = 0
    while i < names.length() {
        if names.get(i) == "XDK_SYS_PROBE" {
            seen = true
        }
        i = i + 1
    }
    print(seen)
    print(names.length() > 0)
    print(platform().length() > 0)
    print(cwd().length() > 0)
    print(pid() > 0)
    print(fileMtime(path) >= 0)

    // stdio pipes: stdin -> child -> stdout, with idempotent close.
    Result<Process, Error> catOpened = spawnProcessPiped("cat")
    Process cat = catOpened.value()
    print(cat.isPiped())
    print(cat.writeStdinText("ping").value())
    print(cat.closeStdin().isOk())
    print(cat.readStdoutAll().value().toString())
    print(cat.wait().value())
    print(cat.close().isOk())
    print(cat.close().isOk())

    // stderr pipe.
    Result<Process, Error> errOpened = spawnProcessPiped("printf err >&2")
    Process errProc = errOpened.value()
    print(errProc.readStderrAll().value().toString())
    print(errProc.wait().value())
    print(errProc.close().isOk())

    // Non-piped processes reject stdio pipe methods.
    Result<Process, Error> plainOpened = spawnProcess("true")
    Process plain = plainOpened.value()
    print(plain.isPiped())
    print(plain.readStdout(1 as Long).isErr())
    print(plain.wait().value())
    print(plain.close().isOk())

    // Signals and process groups: terminate the whole child group.
    print(signalNumber(Signal.Kill) > 0)
    print(signalNumberFromName("TERM") > 0)
    print(signalNumberFromName("NOPE") < 0)
    Result<Process, Error> sleepOpened = spawnProcessPiped("sleep 30")
    Process sleeper = sleepOpened.value()
    print(sleeper.groupId() == sleeper.pid())
    print(sleeper.sendGroupSignal(Signal.Terminate).isOk())
    print(sleeper.wait().value())
    print(sleeper.close().isOk())

    // Resource read subset (no embedded table in this scenario).
    print(resourceExists("missing.txt"))
    print(resourceCount())
    print(readResourceText(null, "missing.txt").isErr())
    print(readResourceText(null, "missing.txt").error().kind() == ErrorKind.NotFound)
    print(listResources(null, "").value().length())
    return 0
}
