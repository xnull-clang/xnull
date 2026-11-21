import xdk.io
import xdk.bytes
import xdk.errors

static Int main() {
    Writer writer = new Writer()
    writer.writeU8(65)
    Bytes suffix = Bytes.fromString("BC")
    writer.writeBytes(suffix)
    print(writer.length())

    Reader reader = new Reader(writer.toBytes())
    print(reader.readU8())
    print(reader.readU8())
    print(reader.readU8())
    print(reader.remaining())
    print(reader.hasRemaining())

    // 严格读取：EOF 是 DataCorrupted，失败不前进。
    Reader checked = new Reader(Bytes.fromString("AB"))
    Result<Int, Error> first = checked.tryReadU8()
    print(first.value())
    print(checked.remaining())
    Result<Bytes, Error> exact = checked.readExact(1)
    print(toHex(exact.value()))
    Result<Bytes, Error> shortExact = checked.readExact(1)
    print(shortExact.isErr())
    print(shortExact.error().kind() == ErrorKind.DataCorrupted)
    print(checked.remaining())

    // toBytes 是副本；close 幂等。
    Writer snapshotWriter = new Writer()
    snapshotWriter.writeU8(1)
    Bytes snapshot = snapshotWriter.toBytes()
    snapshotWriter.writeU8(2)
    print(toHex(snapshot))
    print(toHex(snapshotWriter.toBytes()))
    print(snapshotWriter.flush().isOk())
    print(snapshotWriter.close().isOk())
    print(snapshotWriter.close().isOk())
    print(snapshotWriter.isClosed())

    // Buffered 读：小缓冲跨块，readExact 不足不消费。
    BufferedReader buffered = new BufferedReader(new Reader(Bytes.fromString("ABCDE")), 2)
    print(buffered.remaining())
    print(buffered.readU8())
    Bytes bufferedChunk = buffered.readBytes(3)
    print(toHex(bufferedChunk))
    print(buffered.remaining())
    Result<Bytes, Error> bufferedShort = buffered.readExact(2)
    print(bufferedShort.isErr())
    print(buffered.remaining())
    print(buffered.readU8())
    print(buffered.hasRemaining())
    print(buffered.close().isOk())

    // Buffered 写：flush 才落到底层，close 冲掉余量并关闭底层。
    Writer target = new Writer()
    BufferedWriter bufferedWriter = new BufferedWriter(target)
    bufferedWriter.writeU8(65)
    bufferedWriter.writeBytes(Bytes.fromString("BC"))
    print(bufferedWriter.length())
    print(bufferedWriter.bufferedLength())
    print(target.length())
    print(bufferedWriter.flush().isOk())
    print(target.length())
    print(bufferedWriter.bufferedLength())
    bufferedWriter.writeU8(68)
    print(bufferedWriter.close().isOk())
    print(target.toBytes().toString())
    print(target.isClosed())
    print(bufferedWriter.isClosed())
    print(bufferedWriter.close().isOk())

    // Chain：跨两个源读取，剩余不足时不动。
    ChainReader chain = new ChainReader(new Reader(Bytes.fromString("AB")), new Reader(Bytes.fromString("CD")))
    print(chain.remaining())
    Bytes chainChunk = chain.readBytes(3)
    print(toHex(chainChunk))
    print(chain.remaining())
    print(chain.readU8())
    ChainReader chainShort = new ChainReader(new Reader(Bytes.fromString("A")), new Reader(Bytes.fromString("B")))
    Result<Bytes, Error> chainExact = chainShort.readExact(3)
    print(chainExact.isErr())
    print(chainShort.remaining())

    // Tee：读到哪写到哪；close 只关源，sink 仍可用。
    Writer teeSink = new Writer()
    TeeReader tee = new TeeReader(new Reader(Bytes.fromString("XYZ")), teeSink)
    print(tee.readU8())
    Bytes teeChunk = tee.readBytes(2)
    print(toHex(teeChunk))
    print(teeSink.toBytes().toString())
    print(tee.hasRemaining())
    print(tee.close().isOk())
    print(teeSink.isClosed())

    // Limit：视图长度封顶，不越过底层。
    LimitReader limited = new LimitReader(new Reader(Bytes.fromString("ABCDE")), 3)
    print(limited.remaining())
    print(limited.readU8())
    Bytes limitedChunk = limited.readBytes(5)
    print(toHex(limitedChunk))
    print(limited.remaining())
    Result<Int, Error> limitEof = limited.tryReadU8()
    print(limitEof.isErr())
    print(limited.readExact(1).isErr())

    // LineReader：LF/CRLF/末尾无换行，EOF 返回 null。
    LineReader lines = new LineReader(new Reader(Bytes.fromString("one\r\ntwo\nthree")))
    print(lines.readLine().value())
    print(lines.readLine().value())
    print(lines.readLine().value())
    print(lines.readLine().value() == null)

    // readAll / copyTo：整段读取与整段复制。
    Reader allSource = new Reader(Bytes.fromString("hello"))
    Result<Bytes, Error> all = readAll(allSource)
    print(all.value().toString())
    print(allSource.remaining())
    Writer copySink = new Writer()
    Reader copySource = new Reader(Bytes.fromString("copy"))
    Result<Int, Error> copied = copyTo(copySource, copySink)
    print(copied.value())
    print(copySink.toBytes().toString())
    return 0
}
