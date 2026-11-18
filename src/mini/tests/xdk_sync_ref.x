import xdk.sync

static Int main() {
    AtomicRef<String> r = AtomicRef("a")
    print(r.load())
    r.store("b")
    print(r.load())
    print(r.compareExchange("b", "c"))
    print(r.load())
    return 0
}
