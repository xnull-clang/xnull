import xdk.bytes

static Int main() {
    Bytes a = fromHex("4142")
    Bytes b = fromHex("43")
    print(toHex(concatBytes(a, b)))
    print(toHex(slice(concatBytes(a, b), 1, 3)))
    print(compare(a, b))
    print(toHex(u16BE(4660)))
    print(toHex(u16LE(4660)))
    print(readShortBE(fromHex("1234"), 0))
    print(readShortLE(fromHex("1234"), 0))
    print(toHex(u32BE(305419896)))
    print(readIntBE(fromHex("12345678"), 0))

    ByteBuffer buf = new ByteBuffer()
    buf.push(65)
    buf.append(fromHex("4243"))
    print(toHex(buf.toBytes()))
    print(buf.length())

    print(bitAnd(12, 10))
    print(bitOr(12, 10))
    print(bitXor(12, 10))
    print(shiftLeft(3, 2))
    print(shiftRight(12, 2))

    ByteWriter writer = new ByteWriter()
    writer.writeU8(65)
    writer.writeU16BE(4660)
    writer.writeU32LE(305419896)
    print(toHex(writer.toBytes()))

    ByteReader reader = new ByteReader(writer.toBytes())
    print(reader.readU8())
    print(reader.shortBE())
    print(reader.intLE())
    print(reader.remaining())
    return 0
}
