static Int main() {
    String s = "abc"
    print(s.substring(-1, 2))
    print(s.substring(99, 2).length())
    print(s.substring(1, -5).length())
    print(s.substring(2, 99))
    print(s.indexOf("z"))
    print("".split(",").length())
    print(",".split(",").length())
    print("a,,b".split(",").join("|"))
    print("abc".replace("", "X"))
    print("aaa".replace("aa", "b"))
    print("  a  ".trim())
    print("\t\n a \r\n".trim())
    print("é".length())
    String nb = "\u00a0a\u00a0"
    print(nb.trim() == nb)
    return 0
}
