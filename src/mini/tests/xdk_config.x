import xdk.config

static Int main() {
    Config c = new Config("dev")
    c.set("app.name", "demo")
    c.set("app.port", "8080")
    c.set("app.port", "9090")
    print(c.getOr("app.name", "?"))
    print(c.getOr("app.port", "?"))
    print(c.has("app.host"))
    print(c.length())
    List<String> keys = ["XDK_W5_NAME", "XDK_W5_MISSING"]
    c.loadEnv(keys)
    print(c.getOr("XDK_W5_NAME", "none"))
    print(c.has("XDK_W5_MISSING"))
    print(c.render())
    return 0
}
