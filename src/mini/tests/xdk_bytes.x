import xdk.bytes

static Int main() {
    Bytes raw = fromHex("4142")
    print(toHex(raw))
    print(byteLength(raw))
    print(toUtf8(raw))
    print(toHex(fromUtf8("hi")))
    print(isEmpty(fromUtf8("")))
    return 0
}
