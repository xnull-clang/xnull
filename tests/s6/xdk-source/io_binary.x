// XDK 源码层：二进制 IO + 文件系统操作 + Path
import xdk.sys

static Int main() {
    Result<File, Error> w = openFileWrite("/tmp/xdk-io.bin")
    File f = w.value()
    Bytes b = Bytes.fromString("")
    b.push(65)
    b.push(0)
    b.push(255)
    print(f.write(b).value())
    f.close()

    Result<File, Error> r = openFileRead("/tmp/xdk-io.bin")
    File g = r.value()
    Result<Bytes, Error> data = g.readAll()
    print(data.value().length())
    print(data.value().get(0))
    print(data.value().get(1))
    print(data.value().get(2))
    Result<Int, Error> sz = g.size()
    print(sz.value())
    g.seek(1)
    Result<Bytes, Error> rest = g.read(1)
    print(rest.value().get(0))
    g.close()

    Result<File, Error> a = openFileAppend("/tmp/xdk-io.bin")
    File ap = a.value()
    ap.writeText("XYZ")
    ap.close()
    Result<File, Error> t = openFileRead("/tmp/xdk-io.bin")
    print(t.value().readText().value().length())
    t.value().close()

    print(fileExists("/tmp/xdk-io.bin"))
    print(copyFile("/tmp/xdk-io.bin", "/tmp/xdk-io-copy.bin").isOk())
    print(renameFile("/tmp/xdk-io-copy.bin", "/tmp/xdk-io-moved.bin").isOk())
    print(fileExists("/tmp/xdk-io-moved.bin"))
    print(removeFile("/tmp/xdk-io-moved.bin").isOk())
    print(fileExists("/tmp/xdk-io-moved.bin"))

    print(makeDir("/tmp/xdk-io-dir").isOk())
    print(removeDir("/tmp/xdk-io-dir").isOk())

    Path p = new Path("/a/b/c.txt")
    print(p.isAbsolute())
    print(p.name())
    print(p.parent())
    print(p.ext())
    print(pathJoin("/a/b", "c.txt"))

    Result<ProcessResult, Error> pr = runProcessResult("echo hi")
    print(pr.value().stdout().trim())
    print(pr.value().status())
    return 0
}
