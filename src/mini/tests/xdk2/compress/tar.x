package app.compress
import xdk.compress
import xdk.bytes
import xdk.errors

static String octalText(Long value, Int digits) {
    String digitsText = "01234567"
    String out = ""
    Long current = value
    Int index = 0
    while index < digits {
        Long digit = current % (8 as Long)
        out = digitsText.substring(digit as Int, 1) + out
        current = current / (8 as Long)
        index = index + 1
    }
    return out
}

static Void putOctal(Bytes data, Int offset, Long value, Int digits) {
    String text = octalText(value, digits - 1)
    Int index = 0
    while index < text.length() {
        data.set(offset + index, text.get(index))
        index = index + 1
    }
    data.set(offset + digits - 1, 0)
}

static Void fixChecksum(Bytes data) {
    Int index = 148
    while index < 156 {
        data.set(index, 32)
        index = index + 1
    }
    Long sum = 0 as Long
    index = 0
    while index < 512 {
        sum = sum + (data.get(index) as Long)
        index = index + 1
    }
    String text = octalText(sum, 6)
    index = 0
    while index < 6 {
        data.set(148 + index, text.get(index))
        index = index + 1
    }
    data.set(154, 0)
    data.set(155, 32)
}

static Void putName(Bytes data, String name) {
    Int index = 0
    while index < 100 {
        data.set(index, 0)
        index = index + 1
    }
    index = 0
    while index < name.length() && index < 100 {
        data.set(index, name.get(index))
        index = index + 1
    }
}

static Int main() {
    List<TarEntry> entries = []
    entries.push(TarEntry.file("a.txt", Bytes.fromString("hello"), 420, 1700000000 as Long))
    entries.push(TarEntry.directory("dir", 493, 1700000000 as Long))
    entries.push(TarEntry.file("dir/b.bin", Bytes.fromString("x"), 384, 0 as Long))
    Result<Bytes, Error> written = Tar.write(entries)
    print("write=" + str(written.isOk()) + "," + str(written.value().length()) + "," +
        str(Tar.isTar(written.value())))

    Result<List<TarEntry>, Error> read = Tar.read(written.value())
    TarEntry first = read.value().get(0)
    TarEntry directory = read.value().get(1)
    TarEntry second = read.value().get(2)
    String readLine = "read="
    readLine = readLine + str(read.isOk()) + "," + str(read.value().length()) + ","
    String firstContent = first.content().toString()
    readLine = readLine + first.name() + "," + firstContent + ","
    readLine = readLine + str(first.mode()) + "," + str(first.modifiedSeconds()) + ","
    readLine = readLine + str(first.isDirectory())
    print(readLine)
    String dirLine = "dir="
    dirLine = dirLine + directory.name() + "," + str(directory.isDirectory()) + ","
    dirLine = dirLine + str(directory.size()) + "," + second.name() + ","
    String secondContent = second.content().toString()
    dirLine = dirLine + secondContent
    print(dirLine)

    List<TarEntry> none = []
    Result<Bytes, Error> empty = Tar.write(none)
    Result<List<TarEntry>, Error> emptyRead = Tar.read(empty.value())
    print("empty=" + str(empty.isOk()) + "," + str(empty.value().length()) + "," +
        str(emptyRead.isOk()) + "," + str(emptyRead.value().length()))

    String longName = "prefix/very/long/path/that/exceeds/one/hundred/characters/for/sure/file-name.txt"
    List<TarEntry> longEntries = []
    longEntries.push(TarEntry.file(longName, Bytes.fromString("z"), 420, 1 as Long))
    Result<Bytes, Error> longTar = Tar.write(longEntries)
    Result<List<TarEntry>, Error> longRead = Tar.read(longTar.value())
    print("long=" + str(longTar.isOk()) + "," + str(longRead.isOk()) + "," +
        longRead.value().get(0).name())

    Result<List<TarEntry>, Error> entriesLimit = Tar.readWithLimits(written.value(), 1, 1000)
    Result<List<TarEntry>, Error> bytesLimit = Tar.readWithLimits(written.value(), 10, 3)
    print("limits=" + errorKindName(entriesLimit.error().kind()) + "," +
        errorKindName(bytesLimit.error().kind()))

    Bytes checksumBad = copy(written.value())
    checksumBad.set(0, 99)
    print("checksum=" + errorKindName(Tar.read(checksumBad).error().kind()))

    Bytes truncated = written.value().slice(0, 512)
    print("truncated=" + errorKindName(Tar.read(truncated).error().kind()))

    Bytes unsupported = copy(written.value())
    unsupported.set(156, 50)
    fixChecksum(unsupported)
    print("unsupported=" + errorKindName(Tar.read(unsupported).error().kind()))

    Bytes escape = copy(written.value())
    putName(escape, "../evil")
    fixChecksum(escape)
    print("escape=" + errorKindName(Tar.read(escape).error().kind()))

    String archivePath = "/tmp/xnull_tar_roundtrip.tar"
    Result<Unit, Error> writtenFile = Tar.writeTo(archivePath, entries)
    Result<List<TarEntry>, Error> readFile = Tar.readFrom(archivePath)
    print("files=" + str(writtenFile.isOk()) + "," + str(readFile.isOk()) + "," +
        str(readFile.value().length()))

    String extractDir = "/tmp/xnull_tar_extract_m186"
    Result<Unit, Error> extracted = Tar.extractTo(extractDir, read.value())
    String extractedHex = readFileHexRaw(extractDir + "/a.txt")
    print("extract=" + str(extracted.isOk()) + "," +
        str(fileExistsRaw(extractDir + "/a.txt") != 0) + "," + extractedHex)

    print("isTar=" + str(Tar.isTar(written.value())) + "," +
        str(Tar.isTar(Bytes.fromString("plain"))) + "," +
        str(Tar.isTar(Bytes.fromString(""))))
    return 0
}
