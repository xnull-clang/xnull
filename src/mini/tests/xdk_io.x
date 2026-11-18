import xdk.io
import xdk.bytes

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
    return 0
}
