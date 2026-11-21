import xdk.config
import xdk.fs

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
    Config overrides = new Config("prod")
    overrides.set("app.name", "override")
    overrides.set("app.region", "eu")
    Config merged = c.overlay(overrides)
    print(merged.getOr("app.name", "?"))
    print(merged.getOr("app.region", "?"))
    List<ConfigEntry> entries = []
    entries.push(new ConfigEntry("flag", "on"))
    MapSource source = new MapSource(entries)
    Result<Unit, Error> applied = merged.apply(source)
    print(applied.isOk())
    print(merged.getOr("flag", "off"))
    String path = "/tmp/xnull_core_config.txt"
    writeText(path, "file.key=file\n# comment\nfile.num=42\n")
    FileSource fileSource = new FileSource(path)
    Config fileConfig = new Config("file")
    Result<Unit, Error> loaded = fileConfig.apply(fileSource)
    print(loaded.isOk())
    print(fileConfig.getOr("file.key", "?"))
    print(fileConfig.getOr("file.num", "?"))
    writeText(path, "badline\n")
    Config badConfig = new Config("bad")
    FileSource badSource = new FileSource(path)
    Result<Unit, Error> bad = badConfig.apply(badSource)
    print(bad.isErr())
    removeFile(path)
    return 0
}
