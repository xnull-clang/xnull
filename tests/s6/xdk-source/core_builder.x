import xdk.text

static Int main() {
    StringBuilder builder = StringBuilder()
    builder.append("count=")
    builder.append(7)
    builder.append(true)
    builder.append(2.5)
    builder.append('!')
    StringBuilder chained = builder.append("?")
    print(chained.toString())
    print(builder.length())
    return 0
}
