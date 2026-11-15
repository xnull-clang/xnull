import xdk.text

static Int main() {
    print(padLeft("7", 3, "0"))
    print(repeatText("ab", 2))
    print(contains("hello", "ell"))
    Result<Int, Error> n = parseInt("42")
    Result<Int, Error> bad = parseInt("4x")
    Result<Double, Error> f = parseFloat("-1.25")
    print(n.value())
    print(bad.isErr())
    print(f.value())
    String ws = stringOfByte(11) + "x" + stringOfByte(12)
    print("[" + ws.trim() + "]")
    return 0
}
