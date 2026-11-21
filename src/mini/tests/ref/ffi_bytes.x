// Reference FFI/bytes program: one C call, ByteReader/ByteWriter, error kinds.
import xdk.bytes
import xdk.errors

static Int main() {
    print(demoNow() == 0)
    print(fileSize("src/mini/tests/ref/ffi_bytes.x") > 0)

    ByteWriter writer = new ByteWriter()
    writer.writeU16BE(0x1234)
    writer.writeBytes(fromUtf8("AB"))
    Bytes frame = writer.toBytes()
    print(toHex(frame))

    ByteReader reader = new ByteReader(frame)
    print(reader.shortBE())
    Result<Bytes, Error> body = reader.readExact(2)
    print(body.isOk())
    print(toUtf8(body.value()))

    Result<Bytes, Error> bad = tryFromHex("zz")
    print(bad.isErr())
    print(bad.error().kind() == ErrorKind.InvalidArgument)

    ByteReader shortReader = new ByteReader(fromHex("01"))
    Result<Bytes, Error> shortResult = shortReader.readExact(4)
    print(shortResult.isErr())
    print(shortResult.error().kind() == ErrorKind.DataCorrupted)
    return 0
}
