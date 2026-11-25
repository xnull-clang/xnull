package app.compress
import xdk.compress
import xdk.bytes
import xdk.errors

static Int eocdOffset(Bytes data) {
    Int probe = data.length() - 22
    while probe >= 0 {
        if data.get(probe) == 80 && data.get(probe + 1) == 75 &&
           data.get(probe + 2) == 5 && data.get(probe + 3) == 6 {
            return probe
        }
        probe = probe - 1
    }
    return -1
}

static Int centralOffset(Bytes data) {
    Int eocd = eocdOffset(data)
    if eocd < 0 { return -1 }
    return data.get(eocd + 16) + data.get(eocd + 17) * 256 +
        data.get(eocd + 18) * 65536 + data.get(eocd + 19) * 16777216
}

static String kindOf(Result<Bytes, Error> result) {
    if result.isOk() { return "ok" }
    return errorKindName(result.error().kind())
}

static String kindOfArchive(Result<ZipArchive, Error> result) {
    if result.isOk() { return "ok" }
    return errorKindName(result.error().kind())
}

static String kindOfUnit(Result<Unit, Error> result) {
    if result.isOk() { return "ok" }
    return errorKindName(result.error().kind())
}

static Int main() {
    ZipOptions options = new ZipOptions()
    options.compressionLevel(CompressionLevel.Default)
    options.comment("archive-comment")
    ZipWriter writer = new ZipWriter(options)
    Result<Unit, Error> addA = writer.addFile("a.txt", Bytes.fromString("hello"))
    Result<Unit, Error> addDir = writer.addDirectory("dir")
    Result<Unit, Error> addB = writer.addFile("dir/b.bin", Bytes.fromString("x"))
    Result<Unit, Error> addEmpty = writer.addFile("empty.txt", Bytes.fromString(""))
    print("add=" + str(addA.isOk()) + "," + str(addDir.isOk()) + "," +
        str(addB.isOk()) + "," + str(addEmpty.isOk()) + "," + str(writer.entryCount()))
    Result<Unit, Error> duplicate = writer.addFile("a.txt", Bytes.fromString("again"))
    print("duplicate=" + errorKindName(duplicate.error().kind()))

    Result<Bytes, Error> packed = writer.finish()
    Result<Bytes, Error> packedAgain = writer.finish()
    Result<Unit, Error> afterFinish = writer.addFile("late.txt", Bytes.fromString("z"))
    print("finish=" + str(packed.isOk()) + "," + str(packedAgain.isOk()) + "," +
        str(packed.value().length() == packedAgain.value().length()) + "," +
        errorKindName(afterFinish.error().kind()) + "," + str(writer.isFinished()))

    Result<ZipArchive, Error> opened = ZipArchive.openBytes(packed.value())
    ZipArchive archive = opened.value()
    List<ZipEntry> entries = archive.entries()
    print("entries=" + kindOfArchive(opened) + "," + str(entries.length()) + "," +
        entries.get(0).name() + "," + entries.get(1).name() + "," +
        entries.get(2).name() + "," + str(entries.get(1).isDirectory()))
    Result<Bytes, Error> readA = archive.readEntryByName("a.txt")
    Result<Bytes, Error> readEmpty = archive.readEntryByName("empty.txt")
    String readText = readA.value().toString()
    print("read=" + kindOf(readA) + "," + readText + "," +
        str(readEmpty.value().length()) + "," + str(archive.getOrNull("missing") == null))
    ZipEntry firstEntry = entries.get(0)
    Result<Bytes, Error> readByEntry = archive.readEntry(firstEntry)
    ZipEntry foreign = new ZipEntry("a.txt", 5 as Long, 5 as Long, 0 as Long, 0 as Long, false, null)
    Result<Bytes, Error> readForeign = archive.readEntry(foreign)
    print("read-entry=" + str(readByEntry.isOk()) + "," +
        errorKindName(readForeign.error().kind()))

    Result<Unit, Error> extracted = ZipArchive.openBytes(packed.value()).value().extractTo("/tmp/xnull_zip_m187")
    print("extract=" + kindOfUnit(extracted) + "," +
        str(fileExistsRaw("/tmp/xnull_zip_m187/a.txt") != 0) + "," +
        str(fileExistsRaw("/tmp/xnull_zip_m187/dir/b.bin") != 0))

    archive.close()
    print("close=" + str(archive.isOpen()) + "," +
        errorKindName(archive.readEntryByName("a.txt").error().kind()))

    ZipWriter emptyWriter = new ZipWriter(new ZipOptions())
    Result<Bytes, Error> empty = emptyWriter.finish()
    Result<ZipArchive, Error> emptyArchive = ZipArchive.openBytes(empty.value())
    print("empty=" + str(empty.isOk()) + "," + str(empty.value().length()) + "," +
        kindOfArchive(emptyArchive) + "," + str(emptyArchive.value().entries().length()))

    ZipOptions storeOptions = new ZipOptions()
    storeOptions.compressionLevel(CompressionLevel.None)
    ZipWriter storeWriter = new ZipWriter(storeOptions)
    storeWriter.addFile("s.txt", Bytes.fromString("store-data"))
    Result<Bytes, Error> stored = storeWriter.finish()
    Result<ZipArchive, Error> storedArchive = ZipArchive.openBytes(stored.value())
    Result<Bytes, Error> storedContent = storedArchive.value().readEntryByName("s.txt")
    String storeText = storedContent.value().toString()
    print("store=" + kindOfArchive(storedArchive) + "," + storeText + "," +
        str(stored.value().length() > 0))

    ZipOptions small = new ZipOptions()
    small.maxEntryBytes(2)
    small.maxTotalBytes(4)
    ZipWriter smallWriter = new ZipWriter(small)
    Result<Unit, Error> tooBig = smallWriter.addFile("big", Bytes.fromString("abcd"))
    ZipOptions readLimit = new ZipOptions()
    readLimit.maxEntryBytes(2)
    readLimit.maxTotalBytes(4)
    Result<ZipArchive, Error> limited = ZipArchive.openBytesWithOptions(packed.value(), readLimit)
    print("limits=" + errorKindName(tooBig.error().kind()) + "," +
        errorKindName(limited.error().kind()))

    Bytes data = stored.value()
    Int central = centralOffset(data)
    Bytes badMethod = copy(data)
    badMethod.set(central + 10, 99)
    Bytes encrypted = copy(data)
    encrypted.set(central + 8, 1)
    Bytes badCrc = copy(data)
    badCrc.set(30 + 5, 88)
    Bytes badEocd = data.slice(0, data.length() - 3)
    Bytes zip64 = copy(data)
    Int eocd = eocdOffset(zip64)
    zip64.set(eocd + 10, 255)
    zip64.set(eocd + 11, 255)
    ZipOptions noVerify = new ZipOptions()
    noVerify.verifyCrc(false)
    Result<ZipArchive, Error> laxArchive = ZipArchive.openBytesWithOptions(badCrc, noVerify)
    print("verify=" + kindOfArchive(laxArchive) + "," +
        str(laxArchive.value().readEntryByName("s.txt").isOk()))
    print("errors=" + kindOfArchive(ZipArchive.openBytes(badMethod)) + "," +
        kindOfArchive(ZipArchive.openBytes(encrypted)) + "," +
        kindOf(readEntryCrc(badCrc)) + "," +
        kindOfArchive(ZipArchive.openBytes(badEocd)) + "," +
        kindOfArchive(ZipArchive.openBytes(zip64)))
    return 0
}

static Result<Bytes, Error> readEntryCrc(Bytes data) {
    Result<ZipArchive, Error> archive = ZipArchive.openBytes(data)
    if archive.isErr() { return Err(archive.error()) }
    return archive.value().readEntryByName("s.txt")
}
