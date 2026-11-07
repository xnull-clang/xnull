static String repl(String s, String from, String to) {
    String res = ""
    Int start = 0
    while start <= s.length() {
        String rest = s.substring(start, s.length() - start)
        Int i = rest.indexOf(from)
        if i < 0 {
            res = res + rest
            break
        }
        res = res + rest.substring(0, i) + to
        start = start + i + from.length()
    }
    return res
}
static Int main() {
    print(repl("a,b", "a", "x"))
    return 0
}
