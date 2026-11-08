import xdk.text
static Int main() {
    Result<Int, Error> a = parseInt("42")
    if (a.isOk()) { print(a.value()) }
    Result<Double, Error> f = parseFloat("1.5")
    if (f.isOk()) { print(f.value()) }
    Bytes b = Bytes.fromString("A")
    Result<List<UInt16>, Error> u = utf8ToUtf16(b)
    print(u.isOk())
    if (u.isOk()) {
        Result<Bytes, Error> back = utf16ToUtf8(u.value())
        print(back.isOk())
    }
    print(Format.int(7).width(4).pad('0').build())
    return 0
}
