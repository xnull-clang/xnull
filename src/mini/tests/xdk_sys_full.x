import xdk.sys
import xdk.errors

static Int main() {
    // Full sys unit: File/Dir handles and the same platform/process surface.
    String path = "/tmp/xnull_xdk_sys_full.txt"
    print(writeFileText(path, "abc").value())
    print(readFileText(path).value())

    File writer = openFileWrite(path).value()
    print(writer.isOpen())
    print(writer.isWritable())
    print(writer.writeText("XY").value())
    print(writer.flush().isOk())
    print(writer.close().isOk())
    print(writer.close().isOk())
    print(writer.writeText("z").isErr())
    print(readFileText(path).value())

    File appender = openFileAppend(path).value()
    print(appender.writeText("!").value())
    print(appender.close().isOk())
    print(readFileText(path).value())

    File reader = openFileRead(path).value()
    print(reader.isReadable())
    print(reader.size().value())
    print(reader.seek(1 as Long).isOk())
    print(reader.position().value())
    print(reader.read(2 as Long).value().toString())
    print(reader.readAll().value().toString())
    print(reader.close().isOk())

    Dir directory = openDir("/tmp").value()
    print(directory.isOpen())
    Result<String?, Error> first = directory.next()
    print(first.isOk())
    print(directory.close().isOk())
    print(directory.next().isErr())

    Path p = new Path(path)
    print(p.name())
    print(p.parent().name())
    print(p.extension())
    print(p.isAbsolute())
    print(pathJoin("/tmp", "x").length() > 0)
    print(isDir("/tmp"))
    print(walk("/tmp/xnull_xdk_sys_full_dir").isErr())

    Result<Process, Error> piped = spawnProcessPiped("cat")
    Process process = piped.value()
    print(process.writeStdinText("full").value())
    print(process.closeStdin().isOk())
    print(process.readStdoutText().value())
    print(process.wait().value())
    print(process.close().isOk())

    print(removeFile(path).isOk())
    print(fileExists(path))
    return 0
}
