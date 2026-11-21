// R4 evidence: Config.setChecked (minimal key validation) and apply/overlay.
import xdk.config
import xdk.errors

static Int main() {
    Config config = new Config("dev")
    print(config.setChecked("app.name", "demo").isOk())
    print(config.getOr("app.name", "?"))
    print(config.setChecked("", "x").isErr())
    print(config.setChecked("bad=key", "x").isErr())
    print(config.length())
    print(config.setChecked("app.name", "next").isOk())
    print(config.length())
    print(config.getOr("app.name", "?"))

    List<ConfigEntry> entries = []
    entries.push(new ConfigEntry("flag", "on"))
    entries.push(new ConfigEntry("", "bad"))
    MapSource source = new MapSource(entries)
    Result<Unit, Error> applied = config.apply(source)
    print(applied.isErr())
    print(applied.error().kind() == ErrorKind.InvalidArgument)
    print(config.getOr("flag", "off"))

    Config other = new Config("prod")
    other.set("app.name", "override")
    Config merged = config.overlay(other)
    print(merged.getOr("app.name", "?"))
    print(config.getOr("app.name", "?"))
    return 0
}
