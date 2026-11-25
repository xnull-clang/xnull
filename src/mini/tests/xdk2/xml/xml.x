package app.xml
import xdk.xml
import xdk.bytes
import xdk.errors

static String kindOf(Result<XmlElement, Error> result) {
    if result.isOk() { return "ok" }
    return errorKindName(result.error().kind())
}

static String kindOfText(Result<String, Error> result) {
    if result.isOk() { return "ok" }
    return errorKindName(result.error().kind())
}

static XmlElement? childNamed(XmlElement element, String name) {
    List<XmlElement> children = element.children()
    Int index = 0
    while index < children.length() {
        if children.get(index).name() == name { return children.get(index) }
        index = index + 1
    }
    return null
}

static Int main() {
    String text = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
        "<!-- before root -->\n" +
        "<config version=\"1\" kind='demo'>\n" +
        "  <name>Tom &amp; Jerry</name>\n" +
        "  <empty/>\n" +
        "  <body><![CDATA[a < b & c]]></body>\n" +
        "  <num>&#65;&#x42;</num>\n" +
        "  <nested><leaf attr=\"v\">text</leaf></nested>\n" +
        "</config>\n" +
        "<!-- after root -->"
    Result<XmlElement, Error> parsed = Xml.parse(text)
    print("parse=" + kindOf(parsed))
    XmlElement root = parsed.value()
    print("root=" + root.name() + "," + str(root.attributes().length()) + "," +
        str(root.children().length()) + "," + str(root.textOrNull() == null))
    print("attrs=" + (root.attributeOrNull("version") as String) + "," +
        (root.attributeOrNull("kind") as String) + "," +
        str(root.attributeOrNull("missing") == null))
    XmlElement name = childNamed(root, "name") as XmlElement
    XmlElement empty = childNamed(root, "empty") as XmlElement
    XmlElement body = childNamed(root, "body") as XmlElement
    XmlElement num = childNamed(root, "num") as XmlElement
    XmlElement nested = childNamed(root, "nested") as XmlElement
    XmlElement leaf = childNamed(nested, "leaf") as XmlElement
    print("children=" + (name.textOrNull() as String) + "," + str(empty.children().length()) + "," +
        str(empty.textOrNull() == null) + "," + (body.textOrNull() as String) + "," +
        (num.textOrNull() as String))
    print("nested=" + leaf.name() + "," + (leaf.attributeOrNull("attr") as String) + "," +
        (leaf.textOrNull() as String))

    Result<String, Error> once = Xml.stringify(root)
    print("stringify=" + kindOfText(once))
    Result<XmlElement, Error> again = Xml.parse(once.value())
    Result<String, Error> twice = Xml.stringify(again.value())
    print("round=" + kindOf(again) + "," + str(once.value() == twice.value()) + "," +
        str(once.value().indexOf("&amp;") >= 0) + "," + str(once.value().indexOf("<!--") < 0))

    Result<XmlElement, Error> spaced = Xml.parse("<a>  keep  </a>")
    XmlOptions trimOptions = new XmlOptions()
    trimOptions.preserveWhitespace(false)
    Result<XmlElement, Error> trimmed = Xml.parseWithOptions("<a>  trim  </a>", trimOptions)
    print("space=" + (spaced.value().textOrNull() as String) + "," +
        (trimmed.value().textOrNull() as String))

    print("unclosed=" + kindOf(Xml.parse("<a><b></a>")))
    print("duplicate=" + kindOf(Xml.parse("<a x=\"1\" x=\"2\"/>")))
    print("invalid=" + kindOf(Xml.parse("<1bad/>")))
    print("mixed=" + kindOf(Xml.parse("<a>text<b/></a>")))
    print("entity=" + kindOf(Xml.parse("<a>&unknown;</a>")))

    XmlOptions shallow = new XmlOptions()
    shallow.maxDepth(2)
    XmlOptions tiny = new XmlOptions()
    tiny.maxBytes(3 as Long)
    print("limits=" + kindOf(Xml.parseWithOptions("<a><b><c/></b></a>", shallow)) + "," +
        kindOf(Xml.parseWithOptions("<a/>", tiny)))

    print("doctype=" + kindOf(Xml.parse("<!DOCTYPE a><a/>")))
    XmlOptions permissive = new XmlOptions()
    permissive.allowDoctype(true)
    print("doctype-allow=" + kindOf(Xml.parseWithOptions("<!DOCTYPE a><a/>", permissive)))
    print("doctype-subset=" + kindOf(Xml.parseWithOptions(
        "<!DOCTYPE a [<!ENTITY x \"y\">]><a/>", permissive)))

    Bytes utf8 = Bytes.fromString("<a/>")
    Bytes plain = Bytes.fromString("plain")
    Bytes bom = Bytes.fromString("")
    bom.push(0xEF)
    bom.push(0xBB)
    bom.push(0xBF)
    bom.push(60)
    bom.push(97)
    bom.push(47)
    bom.push(62)
    Bytes utf16 = Bytes.fromString("")
    utf16.push(0xFF)
    utf16.push(0xFE)
    utf16.push(60)
    utf16.push(0)
    print("bytes=" + kindOf(Xml.parseBytes(utf8)) + "," + kindOf(Xml.parseBytes(utf16)))
    print("isxml=" + str(Xml.isXml(utf8)) + "," + str(Xml.isXml(bom)) + "," +
        str(Xml.isXml(plain)) + "," + str(Xml.isXml(Bytes.fromString("<!--x-->"))))

    XmlElement built = new XmlElement("build")
    built.setAttribute("id", "7")
    XmlElement child = new XmlElement("child")
    child.setText("x&y")
    built.addChild(child)
    XmlElement emptyChild = new XmlElement("empty")
    built.addChild(emptyChild)
    Result<String, Error> builtText = Xml.stringify(built)
    print("build=" + kindOfText(builtText) + "," + builtText.value() + "," + built.describe())
    XmlElement copied = built.copy()
    copied.setAttribute("id", "8")
    print("copy=" + (built.attributeOrNull("id") as String) + "," +
        (copied.attributeOrNull("id") as String) + "," +
        str(copied.children().length() == built.children().length()))
    print("remove=" + str(built.removeAttribute("id")) + "," +
        str(built.removeAttribute("missing")))
    return 0
}
