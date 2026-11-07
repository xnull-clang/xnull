static Int main() {
    String text = "a,b"
    print(text.length())
    print(text.substring(0, 1))
    print(text.indexOf(","))
    print(text.trim().length())
    print(text.split(",").join("|"))
    print(text.replace("a", "x"))
    print(text.toUpper())
    print(text.toLower())
    print("abc".startsWith("ab"))
    print("abc".endsWith("c"))
    return 0
}
