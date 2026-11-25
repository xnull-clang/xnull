package app.yaml
import xdk.yaml
import xdk.codec
import xdk.errors

static String kindOf(Result<JsonValue, Error> result) {
    if result.isOk() { return "ok" }
    return errorKindName(result.error().kind())
}

static String kindOfAll(Result<List<YamlDocument>, Error> result) {
    if result.isOk() { return "ok" }
    return errorKindName(result.error().kind())
}

static String kindOfText(Result<String, Error> result) {
    if result.isOk() { return "ok" }
    return errorKindName(result.error().kind())
}

static JsonValue valueAt(JsonValue root, String key) {
    JsonObject object = root.asObject() as JsonObject
    return object.getOr(key, Json.nullValue())
}

static JsonObject objectOf(JsonValue value) {
    return value.asObject() as JsonObject
}

static String numberText(JsonValue value) {
    JsonNumber number = value.asNumber() as JsonNumber
    return number.raw()
}

static String textOf(JsonValue value) {
    return value.asString() as String
}

static Int main() {
    String text = "# app config\n" +
        "server:\n" +
        "  port: 8080\n" +
        "  hosts: [a, b]\n" +
        "  labels: {env: prod, tier: web}\n" +
        "enabled: true\n" +
        "ratio: 1.5\n" +
        "quoted: 'it''s'\n" +
        "escaped: \"line\\nnext\"\n" +
        "defaults: &defs\n" +
        "  timeout: 30\n" +
        "  retries: 3\n" +
        "service:\n" +
        "  <<: *defs\n" +
        "  timeout: 60\n" +
        "items:\n" +
        "  - name: one\n" +
        "    port: 1\n" +
        "  - name: two\n" +
        "    nested:\n" +
        "      flag: false\n"
    Result<JsonValue, Error> parsed = Yaml.parse(text)
    print("parse=" + kindOf(parsed))
    JsonValue root = parsed.value()
    JsonObject server = objectOf(valueAt(root, "server"))
    JsonArray hosts = server.getOr("hosts", Json.nullValue()).asArray() as JsonArray
    JsonObject labels = objectOf(server.getOr("labels", Json.nullValue()))
    print("server=" + numberText(server.getOr("port", Json.nullValue())) + "," +
        str(hosts.length()) + "," + textOf(labels.getOr("env", Json.nullValue())))
    String escaped = textOf(valueAt(root, "escaped"))
    escaped = escaped.replace("\n", "\\n")
    print("scalars=" + str(valueAt(root, "enabled").asBool() as Bool) + "," +
        numberText(valueAt(root, "ratio")) + "," + textOf(valueAt(root, "quoted")) + "," + escaped)
    JsonObject service = objectOf(valueAt(root, "service"))
    print("merge=" + numberText(service.getOr("timeout", Json.nullValue())) + "," +
        numberText(service.getOr("retries", Json.nullValue())))
    JsonArray items = valueAt(root, "items").asArray() as JsonArray
    JsonObject firstItem = objectOf(items.get(0))
    JsonObject secondItem = objectOf(items.get(1))
    JsonObject nestedItem = objectOf(secondItem.getOr("nested", Json.nullValue()))
    print("items=" + str(items.length()) + "," + textOf(firstItem.getOr("name", Json.nullValue())) + "," +
        numberText(firstItem.getOr("port", Json.nullValue())) + "," +
        textOf(secondItem.getOr("name", Json.nullValue())) + "," +
        str(nestedItem.getOr("flag", Json.nullValue()).asBool() as Bool))

    Result<String, Error> once = Yaml.stringify(root)
    Result<JsonValue, Error> again = Yaml.parse(once.value())
    Result<String, Error> twice = Yaml.stringify(again.value())
    print("stringify=" + kindOfText(once))
    print("round=" + kindOf(again) + "," + str(once.value() == twice.value()))

    Result<JsonValue, Error> numeric = Yaml.parse("s: \"123\"\n")
    Result<String, Error> numericOut = Yaml.stringify(numeric.value())
    Result<JsonValue, Error> numericAgain = Yaml.parse(numericOut.value())
    print("string-check=" + str(valueAt(numericAgain.value(), "s").isString()) + "," +
        textOf(valueAt(numericAgain.value(), "s")))

    YamlOptions profileOptions = new YamlOptions()
    profileOptions.profileKey("spring.config.activate.on-profile")
    String docsText = "server:\n  port: 8080\n" +
        "---\nspring:\n  config:\n    activate:\n      on-profile: [prod, staging]\nserver:\n  port: 9090\n"
    Result<List<YamlDocument>, Error> documents = Yaml.parseAllWithOptions(docsText, profileOptions)
    print("multidoc=" + kindOfAll(documents) + "," + str(documents.value().length()) + "," +
        str(documents.value().get(0).profiles().length()) + "," +
        documents.value().get(1).profiles().get(0) + "," +
        documents.value().get(1).profiles().get(1))
    List<String> active = ["prod"]
    List<String> inactive = ["dev"]
    print("active=" + str(documents.value().get(0).isActive(active)) + "," +
        str(documents.value().get(1).isActive(active)) + "," +
        str(documents.value().get(1).isActive(inactive)))

    String propertyText = "root:\n  list:\n    - name: a\n      port: 1\n  flag: false\n  none: null\n  empty: {}\n"
    Result<List<YamlPropertySource>, Error> sources = Yaml.parsePropertySources("app.yml", propertyText)
    YamlPropertySource source = sources.value().get(0)
    print("props=" + str(sources.isOk()) + "," + str(sources.value().length()) + "," +
        source.getOr("root.list[0].name", "") + "," + source.getOr("root.list[0].port", "") + "," +
        source.getOr("root.flag", "") + "," + source.getOr("root.none", "") + "," +
        str(source.contains("root.empty")) + "," + source.name())

    YamlOptions anchorsOff = new YamlOptions()
    anchorsOff.allowAnchors(false)
    YamlOptions aliasesZero = new YamlOptions()
    aliasesZero.maxAliases(0)
    YamlOptions aliasesTiny = new YamlOptions()
    aliasesTiny.maxAliases(1)
    String anchorText = "a: &x 1\nb: *x\nc: *x\n"
    print("anchors=" + kindOf(Yaml.parseWithOptions(anchorText, anchorsOff)) + "," +
        kindOf(Yaml.parseWithOptions(anchorText, aliasesZero)) + "," +
        kindOf(Yaml.parseWithOptions(anchorText, aliasesTiny)))
    YamlOptions noMerge = new YamlOptions()
    noMerge.allowMergeKeys(false)
    print("merge-off=" + kindOf(Yaml.parseWithOptions("a: &x {k: 1}\nb:\n  <<: *x\n", noMerge)))
    print("unknown-alias=" + kindOf(Yaml.parse("a: *missing\n")))

    print("tags=" + kindOf(Yaml.parse("a: !!str 1\n")) + "," +
        kindOf(Yaml.parseWithOptions("a: !!str 1\n", YamlOptionsTagOn())))
    YamlOptions duplicateOff = new YamlOptions()
    duplicateOff.allowDuplicateKeys(false)
    print("duplicate=" + kindOf(Yaml.parseWithOptions("a: 1\na: 2\n", duplicateOff)) + "," +
        kindOf(Yaml.parse("a: 1\na: 2\n")))

    YamlOptions shallow = new YamlOptions()
    shallow.maxDepth(2)
    YamlOptions tiny = new YamlOptions()
    tiny.maxBytes(4 as Long)
    YamlOptions oneDocument = new YamlOptions()
    oneDocument.maxDocuments(1)
    print("limits=" + kindOf(Yaml.parseWithOptions("a:\n  b:\n    c: 1\n", shallow)) + "," +
        kindOf(Yaml.parseWithOptions("a: 1\n", tiny)) + "," +
        kindOfAll(Yaml.parseAllWithOptions("a: 1\n---\nb: 2\n", oneDocument)))

    print("multi-single=" + kindOf(Yaml.parse("a: 1\n---\nb: 2\n")))
    Result<List<YamlPropertySource>, Error> badSource = Yaml.parsePropertySources("", "a: 1\n")
    print("source-name=" + str(badSource.isErr()))
    print("errors=" + kindOf(Yaml.parse("a:\n   b: 1\n  c: 2\n")) + "," +
        kindOf(Yaml.parse("a: \"unterminated\n")) + "," +
        kindOf(Yaml.parse("a: [1, 2\n")))

    YamlOptions version11 = new YamlOptions()
    version11.version(YamlVersion.Yaml11)
    Result<JsonValue, Error> yaml11 = Yaml.parseWithOptions("a: yes\nb: no\n", version11)
    Result<JsonValue, Error> yaml12 = Yaml.parse("a: yes\n")
    JsonObject yaml11Root = objectOf(yaml11.value())
    print("yaml11=" + str(yaml11Root.getOr("a", Json.nullValue()).asBool() as Bool) + "," +
        str(yaml11Root.getOr("b", Json.nullValue()).asBool() as Bool) + "," +
        str(valueAt(yaml12.value(), "a").isString()))

    Result<List<YamlDocument>, Error> many = Yaml.parseAll("a: 1\n---\nb: 2\n")
    Result<String, Error> allText = Yaml.stringifyAll(many.value())
    print("stringify-all=" + kindOfText(allText) + "," + str(many.value().length()) + "," +
        str(allText.value().indexOf("---") >= 0))
    return 0
}

static YamlOptions YamlOptionsTagOn() {
    YamlOptions options = new YamlOptions()
    options.allowStandardTags(true)
    return options
}
