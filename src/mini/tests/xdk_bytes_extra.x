import xdk.bytes

static Int main() {
    Bytes a = fromHex("4142")
    Bytes b = fromHex("43")
    print(toHex(concatBytes(a, b)))
    print(toHex(slice(concatBytes(a, b), 1, 3)))
    print(compare(a, b))
    print(toHex(u16BE(4660)))
    print(toHex(u16LE(4660)))
    print(readU16BE(fromHex("1234"), 0))
    print(readU16LE(fromHex("1234"), 0))
    print(toHex(u32BE(305419896)))
    print(readU32BE(fromHex("12345678"), 0))

    ByteBuffer buf = new ByteBuffer()
    buf.push(65)
    buf.append(fromHex("4243"))
    print(toHex(buf.toBytes()))
    print(buf.length())
    return 0
}
