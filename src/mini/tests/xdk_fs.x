import xdk.fs
import xdk.bytes
import xdk.errors

static Int main() {
    String root = "/tmp/xnull_xdk_fs_probe"
    Result<Unit, Error> cleaned = removeDirAll(root)
    print(makeDir(root).isOk())

    // Result surface: UTF-8 byte counts, non-ASCII, missing path.
    print(writeText(root + "/a.txt", "hello xdk.fs").value())
    print(exists(root + "/a.txt"))
    print(readText(root + "/a.txt").value())
    print(writeText(root + "/u.txt", "é").value())
    print(readText(root + "/u.txt").value())
    Result<String, Error> missing = readText(root + "/missing.txt")
    print(missing.isErr())
    print(missing.error().kind() == ErrorKind.NotFound)
    print(writeBytes(root + "/payload.bin", Bytes.fromString("AB")).value())
    print(toHex(readBytes(root + "/payload.bin").value()))

    // File: Long size/offset, seek, read, idempotent close, write and append.
    Result<File, Error> readOpened = openFileRead(root + "/a.txt")
    File reader = readOpened.value()
    print(reader.isOpen())
    print(reader.size().value())
    print(reader.seek(6 as Long).isOk())
    print(reader.position().value())
    print(reader.read(2 as Long).value().toString())
    print(reader.readAll().value().toString())
    print(reader.close().isOk())
    print(reader.close().isOk())
    print(reader.read(1 as Long).isErr())

    Result<File, Error> writeOpened = openFileWrite(root + "/write.txt")
    print(writeOpened.isOk())
    File writer = writeOpened.value()
    print(writer.writeText("abcdef").value())
    print(writer.seek(2 as Long).isOk())
    print(writer.writeText("XY").value())
    print(writer.flush().isOk())
    print(writer.close().isOk())
    print(readText(root + "/write.txt").value())

    File appender = openFileAppend(root + "/write.txt").value()
    print(appender.writeText("!").value())
    print(appender.close().isOk())
    print(readText(root + "/write.txt").value())

    // Dir: entries() consumes the handle; next() after close is an error.
    Result<Dir, Error> dirOpened = openDir(root)
    Dir directory = dirOpened.value()
    print(directory.entries().value().length())
    print(directory.close().isOk())
    print(directory.next().isErr())

    // Path: pure lexical operations.
    Path path = new Path(root + "/sub/c.txt")
    print(path.name())
    print(path.parent().name())
    print(path.extension())
    print(path.isAbsolute())
    print(path.join("d.txt").name())
    Path messy = new Path("a/../b/./c")
    print(messy.normalize().toString())

    // Metadata, permissions, links.
    print(metadata(root + "/a.txt").value().isFile())
    print(metadata(root + "/a.txt").value().size)
    print(metadata(root).value().isDirectory())
    print(linkMetadata(root + "/a.txt").value().isFile())
    print(setPermissions(root + "/a.txt", 384).isOk())
    print(permissions(root + "/a.txt").value())
    print(metadata(root + "/a.txt").value().permissions)
    print(metadata(root + "/a.txt").value().isExecutable())
    print(createSymlink(root + "/a.txt", root + "/link.txt").isOk())
    print(readLink(root + "/link.txt").value() == root + "/a.txt")
    print(metadata(root + "/link.txt").value().isFile())
    print(linkMetadata(root + "/link.txt").value().isSymlink())
    print(isSymlink(root + "/link.txt"))
    print(removeFile(root + "/link.txt").isOk())
    print(createHardLink(root + "/a.txt", root + "/hard.txt").isOk())
    print(readText(root + "/hard.txt").value())
    print(removeFile(root + "/hard.txt").isOk())

    // Atomic write.
    print(writeTextAtomic(root + "/atomic.txt", "atomic").value())
    print(readText(root + "/atomic.txt").value())

    // mkdirAll, walk, glob.
    print(mkdirAll(root + "/deep/er").isOk())
    print(isDir(root + "/deep/er"))
    print(writeText(root + "/deep/er/nested.txt", "n").value())
    print(walk(root).value().length())
    print(glob(root + "/*.txt").value().length())
    print(glob(root + "/**/*.txt").value().length())

    // Temp leases are removed on close and close is idempotent.
    Result<TempFile, Error> tempOpened = createTempFile("xnull-fs-")
    print(tempOpened.isOk())
    TempFile temporary = tempOpened.value()
    print(exists(temporary.path))
    print(temporary.close().isOk())
    print(exists(temporary.path))
    print(temporary.close().isOk())

    Result<TempDir, Error> tempDirOpened = createTempDir("xnull-fs-")
    print(tempDirOpened.isOk())
    TempDir temporaryDir = tempDirOpened.value()
    print(isDir(temporaryDir.path))
    print(writeText(temporaryDir.path + "/inside.txt", "x").value())
    print(walk(temporaryDir.path).value().length())
    print(temporaryDir.close().isOk())
    print(exists(temporaryDir.path))

    // Copy/rename.
    print(copyFile(root + "/a.txt", root + "/copy.txt").isOk())
    print(readText(root + "/copy.txt").value())
    print(renameFile(root + "/copy.txt", root + "/moved.txt").isOk())
    print(exists(root + "/moved.txt"))
    print(exists(root + "/copy.txt"))

    print(removeDirAll(root).isOk())
    print(exists(root))
    return 0
}
