import xdk.sync

static Int main() {
    AtomicRef<String> value = AtomicRef<String>("a")
    print(value.load())
    value.store("b")
    print(value.load())
    String expected = value.load()
    print(value.compareExchange(expected, "c"))
    print(value.load())
    print(value.compareExchange(expected, "x"))
    print(value.load())
    return 0
}
