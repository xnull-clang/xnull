package app.toml
import xdk.toml
import xdk.codec
import xdk.errors

static String kindOf(Result<JsonValue, Error> result) {
    if result.isOk() { return "ok" }
    return errorKindName(result.error().kind())
}

static String kindOfText(Result<String, Error> result) {
    if result.isOk() { return "ok" }
    return errorKindName(result.error().kind())
}

static JsonValue? lookup(JsonValue root, String path) {
    JsonObject current = root.asObject() as JsonObject
    List<String> parts = path.split(".")
    Int index = 0
    while index < parts.length() {
        JsonValue? next = current.getOrNull(parts.get(index))
        if next == null { return null }
        if index == parts.length() - 1 { return next }
        JsonValue value = next as JsonValue
        if !value.isObject() { return null }
        current = value.asObject() as JsonObject
        index = index + 1
    }
    return null
}

static String numberAt(JsonValue root, String path) {
    JsonValue value = lookup(root, path) as JsonValue
    JsonNumber number = value.asNumber() as JsonNumber
    return number.raw()
}

static String stringAt(JsonValue root, String path) {
    JsonValue value = lookup(root, path) as JsonValue
    return value.asString() as String
}

static Bool boolAt(JsonValue root, String path) {
    JsonValue value = lookup(root, path) as JsonValue
    return value.asBool() as Bool
}

static Int main() {
    String text = "# config\n" +
        "title = \"TOML Example\"\n" +
        "enabled = true\n" +
        "count = 42\n" +
        "ratio = 1.5\n" +
        "hex = 0x1f\n" +
        "oct = 0o17\n" +
        "bin = 0b101\n" +
        "big = 1_000\n" +
        "escaped = \"line\\nquote\\\"tab\\tunicode\\u0041\"\n" +
        "literal = 'raw \\n'\n" +
        "tags = [\"a\", \"b\", 3, true]\n" +
        "point = { x = 1, y = 2 }\n" +
        "owner.name = \"Tom\"\n" +
        "\"quoted key\" = 7\n" +
        "[server]\n" +
        "host = \"localhost\"\n" +
        "port = 8080\n" +
        "[server.tls]\n" +
        "enabled = false\n" +
        "[[items]]\n" +
        "name = \"one\"\n" +
        "[items.meta]\n" +
        "order = 1\n" +
        "[[items]]\n" +
        "name = \"two\"\n"
    Result<JsonValue, Error> parsed = Toml.parse(text)
    print("parse=" + kindOf(parsed))
    JsonValue root = parsed.value()
    print("values=" + stringAt(root, "title") + "," + str(boolAt(root, "enabled")) + "," +
        numberAt(root, "count") + "," + numberAt(root, "ratio") + "," +
        numberAt(root, "hex") + "," + numberAt(root, "oct") + "," +
        numberAt(root, "bin") + "," + numberAt(root, "big"))
    String escaped = stringAt(root, "escaped").replace("\n", "\\n").replace("\t", "\\t")
    print("escape=" + escaped + "," + stringAt(root, "literal"))
    print("dotted=" + stringAt(root, "owner.name") + "," + numberAt(root, "quoted key") + "," +
        numberAt(root, "point.x") + "," + numberAt(root, "point.y"))
    print("server=" + stringAt(root, "server.host") + "," + numberAt(root, "server.port") + "," +
        str(boolAt(root, "server.tls.enabled")))
    JsonValue items = lookup(root, "items") as JsonValue
    JsonArray itemArray = items.asArray() as JsonArray
    print("items=" + str(itemArray.length()) + "," +
        stringAt(itemArray.get(0), "name") + "," + numberAt(itemArray.get(0), "meta.order") + "," +
        stringAt(itemArray.get(1), "name"))

    Result<String, Error> once = Toml.stringify(parsed.value())
    print("stringify=" + kindOfText(once))
    Result<JsonValue, Error> reparsed = Toml.parse(once.value())
    Result<String, Error> twice = Toml.stringify(reparsed.value())
    print("round=" + kindOf(reparsed) + "," + str(once.value() == twice.value()))
    print("stable=" + str(once.value().length() > 0) + "," + str(once.value().indexOf("[[items]]") >= 0))

    print("empty=" + kindOf(Toml.parse("  # comment\n\n")))
    TomlOptions shallow = new TomlOptions()
    shallow.maxDepth(2)
    TomlOptions tiny = new TomlOptions()
    tiny.maxBytes(4 as Long)
    print("limits=" + kindOf(Toml.parseWithOptions("a = [[[1]]]\n", shallow)) + "," +
        kindOf(Toml.parseWithOptions("a = 1\n", tiny)))

    print("dup=" + kindOf(Toml.parse("a = 1\na = 2\n")))
    print("dup-table=" + kindOf(Toml.parse("[a]\nx=1\n[a]\ny=2\n")))
    print("conflict=" + kindOf(Toml.parse("a = 1\n[a]\nx=2\n")))
    print("closed=" + kindOf(Toml.parse("a = { b = 1 }\na.c = 2\n")))
    print("date=" + kindOf(Toml.parse("a = 1979-05-27\n")))
    print("time=" + kindOf(Toml.parse("a = 07:32:00\n")))
    print("multiline=" + kindOf(Toml.parse("a = \"\"\"x\"\"\"\n")))
    print("inf=" + kindOf(Toml.parse("a = inf\n")))
    print("syntax=" + kindOf(Toml.parse("a = [1, 2\n")))

    Result<String, Error> scalar = Toml.stringify(Json.string("x"))
    Result<String, Error> emptyObject = Toml.stringify(Json.object())
    print("write-root=" + kindOfText(scalar) + "," + kindOfText(emptyObject) + "," +
        str(emptyObject.value().length()))

    JsonObject custom = new JsonObject()
    custom.set("weird key", Json.string("a\nb"))
    custom.set("empty", Json.object())
    custom.set("list", Json.array())
    JsonValue customRoot = new JsonValue(JsonKind.Object, false, null, null, null, custom)
    Result<String, Error> rendered = Toml.stringify(customRoot)
    print("write-custom=" + kindOfText(rendered) + "," +
        str(rendered.value().indexOf("\"weird key\" = \"a\\nb\"") >= 0) + "," +
        str(rendered.value().indexOf("list = []") >= 0) + "," +
        str(rendered.value().indexOf("[empty]") >= 0))
    return 0
}
