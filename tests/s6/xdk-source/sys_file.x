// XDK 源码层：sys 文件（整文件文本）与目录/子进程
import xdk.sys

static Int main() {
    Result<File, Error> w = openFileWrite("/tmp/xdk-src-file.txt")
    File f = w.value()
    f.write("hello\n")
    f.writeLine("world")
    f.close()
    print(f.isOpen())

    Result<File, Error> r = openFileRead("/tmp/xdk-src-file.txt")
    File g = r.value()
    print(g.readText().value())
    g.close()

    Result<File, Error> missing = openFileRead("/tmp/xdk-src-none.txt")
    print(missing.isErr())

    Result<Dir, Error> d = openDir(".")
    Dir dir = d.value()
    Int n = 0
    String name = dir.next()
    while name.length() > 0 {
        n = n + 1
        name = dir.next()
    }
    dir.close()
    print(n > 0)

    print(runProcess("exit 7"))
    return 0
}
