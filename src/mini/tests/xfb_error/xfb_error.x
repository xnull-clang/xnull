static Int main() {
    Int32 code = 0
    Int64 v = div(10, 2, code)
    print(v)
    print(code == 0)

    Int32 bad = 0
    Int64 z = div(1, 0, bad)
    print(z)
    print(bad == 2)

    Bytes bytes = Bytes.fromString("abc")
    print(byteAt(bytes, 1) == 98)
    return 0
}
