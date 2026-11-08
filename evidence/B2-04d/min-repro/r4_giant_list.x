class Tok {
    Int kind = 0
    String text = ""
    Tok(Int k, String t) {
        self.kind = k
        self.text = t
    }
}
class P {
    List<Tok> ts = []
    Int i = 0
    P(List<Tok> xs) { self.ts = xs }
    Tok cur() { return self.ts.get(self.i) }
    Tok next() { Tok t = self.cur(); self.i = self.i + 1; return t }
    String run() {
        String res = ""
        Int k = 0
        while k < self.ts.length() {
            Tok t = self.next()
            res = res + t.text
            k = k + 1
        }
        return res
    }
}
static Int main() {
    List<Tok> xs = []
    Int i = 0
    while i < 20000 {
        xs.push(new Tok(i, "abc" + str(i)))
        i = i + 1
    }
    P p = new P(xs)
    String s = p.run()
    print(str(s.length()))
    return 0
}
