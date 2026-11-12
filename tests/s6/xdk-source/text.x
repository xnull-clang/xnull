// XDK 源码层：text（Format / parse / Regex / 编码）
import xdk.text

static Int main() {
    Result<Int, Error> i = parseInt("42")
    print(i.value())
    Result<Int, Error> bad = parseInt("4x")
    print(bad.isErr())
    Result<Double, Error> d = parseFloat("3.5")
    print(d.value())
    Format f = formatInt(7).width(4).pad('0')
    print(f.build())
    Result<Regex, Error> re = regexCompile("a.c")
    print(re.value().isMatch("abc"))
    Bytes raw = Bytes.fromString("A")
    Result<Utf16, Error> u = utf8ToUtf16(raw)
    print(u.value().length())
    Result<Bytes, Error> back = utf16ToUtf8(u.value().units)
    print(back.value().length())
    return 0
}
