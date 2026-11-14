import xdk.text

static Int main() {
    Text text = Text.fromString("hello")
    print(text.length())
    print(text.codePointCount())
    print(text.toString())
    Text same = Text.fromString("hello")
    print(text.compareTo(same))
    StringBuilder builder = StringBuilder()
    builder.append("count=")
    builder.append(7)
    print(builder.toString())
    print(builder.length())
    return 0
}
