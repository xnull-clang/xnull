static Int main() {
    String s = "a,b"
    List<String> parts = []
    Int start = 0
    while start <= s.length() {
        String rest = s.substring(start, s.length() - start)
        Int i = rest.indexOf(",")
        if i < 0 {
            parts.push(rest)
            break
        }
        parts.push(rest.substring(0, i))
        start = start + i + 1
    }
    print(parts.length())
    print(parts.get(0))
    return 0
}
