import xdk.sys

static Int main() {
    String path = "/tmp/xnull-m7-sys-test.txt"
    Result<File, Error> wf = openFileWrite(path)
    if wf.isErr() {
        print("openw-err")
        return 1
    }
    File w = wf.value()
    Result<Int, Error> wr = w.writeText("alpha\nbeta")
    print(wr.value())
    w.close()

    Result<File, Error> rf = openFileRead(path)
    File r = rf.value()
    print(r.readText().value().trim())
    print(r.size().value())
    r.close()

    Result<File, Error> missing = openFileRead("/tmp/xnull-m7-missing.txt")
    print(missing.isErr())

    Result<Dir, Error> od = openDir("/tmp")
    Dir d = od.value()
    print(d.next().length() > 0)
    d.close()

    Result<ProcessResult, Error> pr = runProcessResult("printf hi")
    print(pr.value().stdout())
    print(runProcess("exit 3"))
    removeFile(path)
    print(fileExists(path))
    return 0
}
