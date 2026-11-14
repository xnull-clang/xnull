import xdk.text

static Int main() {
    Bytes value = Bytes.fromString("ab")
    value.set(1, 99)
    Bytes suffix = Bytes.fromString("Z")
    value.append(suffix)
    print(value.length())
    print(value.get(1))
    print(value.get(2))
    return 0
}
