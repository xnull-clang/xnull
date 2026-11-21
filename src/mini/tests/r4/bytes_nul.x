import xdk.bytes

static Int main() {
    Bytes a = fromUtf8("ab\0cd")
    print(nulIndex(a))
    print(hasNul(a))
    print(toHex(nulPrefix(a)))
    print(toHex(withNulTerminator(fromUtf8("hi"))))
    print(toHex(withNulTerminator(fromHex("686900"))))
    print(toHex(withoutTrailingNul(fromHex("686900"))))
    print(nulIndex(fromUtf8("plain")))
    print(hasNul(fromUtf8("plain")))
    print(toHex(nulPrefix(fromUtf8("plain"))))
    print(toHex(withoutTrailingNul(fromHex("6869"))))
    Bytes zero = fromHex("00ff")
    print(nulIndex(zero))
    print(toHex(nulPrefix(zero)) == "")
    print(toHex(withNulTerminator(fromHex(""))))
    print(toHex(withoutTrailingNul(fromHex("00"))) == "")
    return 0
}
