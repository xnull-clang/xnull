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

    Result<Regex, Error> r = regexCompile("a+b")
    Regex re = r.value()
    print(re.isMatch("xxaabyy"))
    print(re.replaceAll("aab x aaab", "!"))
    return 0
}
