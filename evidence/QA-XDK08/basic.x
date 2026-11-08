import xdk.text
import xdk.errors
static Int main() {
    Result<Int, Error> a = parseInt("42")
    print(a.value())
    Result<Int, Error> bad = parseInt("x")
    print(bad.isErr())
    String s = Format.int(7).width(4).pad('0').build()
    print(s)
    Result<Regex, Error> re = Regex.compile("a+")
    print(re.value().isMatch("aaa"))
    print(re.value().isMatch("b"))
    Result<Regex, Error> badre = Regex.compile("*")
    print(badre.isErr())
    return 0
}
