// R4 evidence: S1 §1.4.3/§1.4.4 string and character escape sequences.
// Covers embedded NUL, raw strings (single-line and multi-line), and a
// non-ASCII Char literal in addition to the ordinary escape table.
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

    // Embedded NUL must be preserved as a byte, not terminate the string.
    String nul = "a\0b"
    print(nul.length())
    print(codePointAt(nul, 0))
    print(codePointAt(nul, 1))
    print(codePointAt(nul, 2))
    print(nul == "a")
    String nulDigit = "a\01"
    print(nulDigit.length())
    print(codePointAt(nulDigit, 0))
    print(codePointAt(nulDigit, 1))
    print(codePointAt(nulDigit, 2))

    // Raw strings preserve backslashes literally.
    String raw = r"a\nb"
    print(raw.length())
    print(codePointAt(raw, 0))
    print(codePointAt(raw, 1))
    print(codePointAt(raw, 2))
    print(codePointAt(raw, 3))
    String rawUnicode = r"\u{1F600}"
    print(rawUnicode.length())
    print(rawUnicode)
    String rawBad = r"\q"
    print(rawBad.length())
    print(codePointAt(rawBad, 0))
    print(codePointAt(rawBad, 1))

    // Multi-line raw string: newline is preserved, \n stays literal.
    String multi = r"""x
y\n"""
    print(multi.length())
    print(codePointAt(multi, 0))
    print(codePointAt(multi, 1))
    print(codePointAt(multi, 2))
    print(codePointAt(multi, 3))
    print(codePointAt(multi, 4))

    // Non-ASCII Char literal and the same scalar in a string.
    Char big = '\u{1F600}'
    print(big == '\u{1F600}')
    print(big as Int)
    String bigText = "\u{1F600}"
    print(bigText.length())
    print(codePointAt(bigText, 0))
    return 0
}
