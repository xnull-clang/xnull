package xdk_io_2x
import xdk.io
import xdk.bytes
import xdk.errors

static Int main() {
    Context context = Context.background()
    ByteArrayReader reader = new ByteArrayReader(Bytes.fromString("hello"))
    Bytes buffer = Bytes.alloc(2)
    Int read = reader.read(context, buffer).value()
    String bufferText = buffer.toString()
    print("byte-reader=" + str(read) + "," + bufferText + "," + str(reader.position()) +
        "," + str(reader.seek(1 as Long, SeekOrigin.Start).value()) +
        "," + str(reader.size().value()) + "," + str(reader.isOpen()))
    print("byte-reader-close=" + str(reader.close().isOk()) + "," + str(reader.isOpen()))
    ByteArrayWriter writer = new ByteArrayWriter()
    writer.writeAll(context, Bytes.fromString("ab"))
    writer.writeAll(context, Bytes.fromString("cd"))
    String writerText = writer.toBytes().toString()
    print("byte-writer=" + writerText + "," + str(writer.length()) + "," + str(writer.isOpen()))
    StringWriter stringWriter = new StringWriter()
    stringWriter.writeText("a")
    stringWriter.writeAll(context, Bytes.fromString("b"))
    print("string-writer=" + stringWriter.toString() + "," + str(stringWriter.length()) +
        "," + str(stringWriter.close().isOk()))
    StringReader stringReader = new StringReader("xyz")
    Bytes one = Bytes.alloc(1)
    stringReader.read(context, one)
    String oneText = one.toString()
    print("string-reader=" + oneText + "," + stringReader.readAllText() +
        "," + str(stringReader.position()) + "," + seekOriginName(SeekOrigin.End))
    return 0
}
