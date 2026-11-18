import xdk.sync

static Int main() {
    Channel<Int> c = Channel(1)
    print(c.send(7).isOk())
    print(c.receive().value())
    return 0
}
