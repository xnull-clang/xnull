import xdk.text

static Int main() {
    Bytes b = Bytes.fromString("Aé中😀")
    Result<List<UInt16>, Error> u = utf8ToUtf16(b)
    print(u.value().length())
    print(u.value().get(2))
    print(u.value().get(3))
    Result<Bytes, Error> back = utf16ToUtf8(u.value())
    print(back.value().length())
    print(back.value().get(9))
    return 0
}
