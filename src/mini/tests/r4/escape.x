// R4 evidence: S1 §1.4.3/§1.4.4 string and character escape sequences.
// The \0 case is intentionally excluded: it truncates at the C string
// boundary (see R4-EVIDENCE.md); raw strings are also unsupported.
import xdk.text

static String charText(Char value) {
    List<FormatArgument> arguments = []
    arguments.push(FormatArgument.ofChar(value))
    return printf("%c", arguments).value()
}

static Void dumpChar(Char value) {
    String text = charText(value)
    print(text.length())
    print(codePointAt(text, 0))
}

static Int main() {
    String s = "n=\n r=\r t=\t bs=\\ sq=\' dq=\""
    print(s.length())
    print(codePointAt(s, 2))
    print(codePointAt(s, 6))
    print(codePointAt(s, 10))

    String hex = "\x41\x7f"
    print(hex.length())
    print(codePointAt(hex, 0))
    print(codePointAt(hex, 1))
    String u4 = "\u00e9"
    print(u4.length())
    print(codePointAt(u4, 0))
    String u8 = "\u{1F600}"
    print(u8.length())
    print(codePointAt(u8, 0))

    dumpChar('\n')
    dumpChar('\r')
    dumpChar('\t')
    dumpChar('\\')
    dumpChar('\'')
    dumpChar('\"')
    return 0
}
