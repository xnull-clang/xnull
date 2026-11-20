import xdk.bytes

static Int main() {
    print(toHex(fromHex("4A4b")))
    print(tryFromHex("4A4b").isOk())
    print(tryFromHex("ABC").isErr())
    print(tryFromHex("4G").isErr())

    Result<Int, Error> got = tryGetByte(fromHex("41"), 0)
    print(got.value())
    Result<Int, Error> missing = tryGetByte(fromHex("41"), 2)
    print(missing.isErr())
    Bytes editable = fromHex("41")
    Result<Unit, Error> set = trySetByte(editable, 0, 66)
    print(set.isOk())
    print(toHex(editable))

    print(sliceChecked(fromHex("4142"), 0, 2).isOk())
    print(sliceChecked(fromHex("4142"), 1, 0).isErr())

    Bytes source = fromHex("4142")
    Bytes copied = copy(source)
    copied.set(0, 67)
    print(toHex(source))
    print(toHex(copied))

    ByteWriter writer = new ByteWriter()
    writer.writeU8(1)
    Bytes snapshot = writer.toBytes()
    writer.writeU8(2)
    print(toHex(snapshot))
    Bytes taken = writer.takeBytes()
    print(toHex(taken))
    print(writer.length())

    Long value64 = 4294967295
    print(toHex(u64LE(value64)))
    print(toHex(u64BE(value64)))
    print(readIntBE(fromHex("FFFFFFFF"), 0))
    print(readLongLE(fromHex("FFFFFFFF00000000"), 0))
    print(readLongLE(fromHex("FFFFFFFFFFFFFFFF"), 0))
    print(readLongBE(fromHex("FFFFFFFFFFFFFFFF"), 0))
    print(toHex(u64LE(-1)))
    print(toHex(u64BE(-1)))

    print(popCount(0))
    print(popCount(-1))
    print(leadingZeros(1))
    print(leadingZeros(0))
    print(trailingZeros(8))
    print(trailingZeros(0))
    print(popCountLong(-1))
    print(leadingZerosLong(1))
    print(trailingZerosLong(8))

    ByteReader reader = new ByteReader(fromHex("41"))
    print(reader.readU8())
    Result<Int, Error> eof = reader.tryReadU8()
    print(eof.isErr())
    print(reader.position())

    ByteReader shortReader = new ByteReader(fromHex("41"))
    Result<Int, Error> shortRead = shortReader.tryShortBE()
    print(shortRead.isErr())
    print(shortReader.position())

    Bytes initial = fromHex("41")
    ByteBuffer buffer = byteBufferFrom(initial)
    initial.set(0, 66)
    print(toHex(buffer.toBytes()))
    print(buffer.put(0, 67).isOk())
    print(buffer.get(0).value())
    print(buffer.get(5).isErr())
    return 0
}
