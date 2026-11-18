import xdk.sync

static Int main() {
    Channel<Int> c = Channel(1)
    print(c.send(7).isOk())
    print(c.receive().value())
    c.close()
    print(c.send(9).isErr())
    print(c.receive().isErr())
    return 0
}
