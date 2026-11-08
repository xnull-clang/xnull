class Tok {
    Int kind = 0
    String text = ""
    Tok(Int k, String t) {
        self.kind = k
        self.text = t
    }
}
static Int main() {
    List<Tok> xs = []
    Int i = 0
    while i < 20000 {
        xs.push(new Tok(i, "abc" + str(i)))
        i = i + 1
    }
    Int n = 0
    i = 0
    while i < xs.length() {
        Tok t = xs.get(i)
        n = n + t.text.length()
        i = i + 1
    }
    print(str(n))
    return 0
}
