import xdk.text

static Int main() {
    print(padLeft("7", 3, "0"))
    print(padRight("7", 3, "."))
    print(reverse("abc"))
    print(isEmpty(""))
    print(isBlank(" \t"))
    print(equalsIgnoreCase("AbC", "aBc"))
    print(capitalize("abc"))
    print(truncate("abcdef", 4))
    print(levenshtein("kitten", "sitting"))
    print(codePointAt("éA", 0))

    print(formatInt(7).width(4).pad('0').build())
    print(formatString("x").width(3).pad('.').build())

    Result<Regex, Error> r = regexCompile("a+b")
    Regex re = r.value()
    print(re.isMatch("xxaabyy"))
    print(re.replaceAll("aab x aaab", "!"))

    Bytes b = Bytes.fromString("é")
    Result<Utf16, Error> u = utf8ToUtf16(b)
    print(u.isOk())
    if u.isOk() {
        print(u.value().length())
    }
    return 0
}
