import xdk.text
import xdk.bytes

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

    // T0-X Unicode: code points, UTF-8 repair, UTF-16 rejection.
    print(codePointAt("éA", 0))
    print(codePointAt("éA", 2))
    print(codePointLen("é", 0))
    print(codePointCount("éA"))
    print(fromCodePoint(233))
    print(codePointAt(fromCodePoint(128512), 0))
    print(codePointCount(fromCodePoint(128512)))
    Result<Utf16, Error> repaired = utf8ToUtf16(fromHex("ff"))
    print(repaired.isOk())
    print(repaired.value().length())
    print(repaired.value().get(0) as Int)
    print(utf16ToText(repaired.value()).value())
    List<UInt16> loneSurrogate = []
    loneSurrogate.push(0xD800)
    print(utf16ToUtf8(loneSurrogate).isErr())

    // T0-X Regex: intervals, POSIX classes, capture groups, Unicode atoms.
    Result<Regex, Error> ere = regexCompile("^(ab)+c{2,3}$")
    print(ere.isOk())
    print(ere.value().isMatch("abcc"))
    print(ere.value().isMatch("ababcbc"))
    print(regexCompile("[[:alpha:]]+[[:digit:]]{2}").value().isMatch("abc42"))
    List<Match> groups = regexCompile("(a+)(b+)").value().findAll("xxaaabb")
    print(groups.length())
    print(groups.get(0).group(0))
    print(groups.get(0).group(1))
    print(groups.get(0).group(2))
    print(regexCompile("é+").value().isMatch("éé"))
    print(regexCompile(".").value().isMatch("é"))
    print(regexCompile("a{2,1}").isErr())

    // T0-X printf Format.
    List<FormatArgument> formatArgs = []
    formatArgs.push(FormatArgument.ofInt(7))
    formatArgs.push(FormatArgument.ofText("ok"))
    formatArgs.push(FormatArgument.ofFloat(3.14159))
    formatArgs.push(FormatArgument.ofInt(255))
    formatArgs.push(FormatArgument.ofBool(true))
    formatArgs.push(FormatArgument.ofChar('A'))
    print(printf("%04d|%-4s|%.2f|%#x|%b|%c|%%", formatArgs).value())
    List<FormatArgument> signedArg = []
    signedArg.push(FormatArgument.ofInt(-42))
    print(printf("%+06d", signedArg).value())
    List<FormatArgument> exponentArg = []
    exponentArg.push(FormatArgument.ofFloat(1234.5))
    print(printf("%.3e", exponentArg).value())
    List<FormatArgument> missingArgs = []
    print(printf("%d", missingArgs).isErr())
    List<FormatArgument> wrongType = []
    wrongType.push(FormatArgument.ofText("x"))
    print(printf("%d", wrongType).isErr())
    return 0
}
