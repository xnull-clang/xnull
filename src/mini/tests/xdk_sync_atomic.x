import xdk.sync

static Int main() {
    AtomicInt a = AtomicInt(1)
    print(a.load())
    a.store(2)
    print(a.load())
    print(a.compareExchange(2, 3))
    print(a.load())

    AtomicBool b = AtomicBool(false)
    print(b.load())
    b.store(true)
    print(b.compareExchange(true, false))
    print(b.load())
    return 0
}
