import xdk.config

static Int main() {
    Config c = new Config("dev")
    c.set("app.port", "9090")
    c.set("app.long", "9000000000")
    c.set("app.debug", "true")
    c.set("app.ratio", "3.5")
    c.set("app.bad", "nope")
    Result<Int, Error> port = c.getInt("app.port")
    print(port.isOk())
    print(port.value())
    Result<Long, Error> big = c.getLong("app.long")
    print(big.isOk())
    print(big.value())
    print(c.getBool("app.debug").value())
    print(c.getDouble("app.ratio").value())
    print(c.getInt("missing").isErr())
    print(c.getInt("missing").error().kind() == ErrorKind.NotFound)
    print(c.getLong("app.bad").isErr())
    print(c.getBool("app.bad").isErr())
    print(c.getDouble("app.bad").isErr())
    print(c.getInt("app.bad").isErr())
    return 0
}
