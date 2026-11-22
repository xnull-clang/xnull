import xdk.functional
class Holder {
    Seq<String> items = Seq.empty()
}
static Seq<Int> makeEmpty() {
    return Seq.empty()
}
static Int main() {
    Seq<Int> a = Seq.empty()
    Seq<String> s = Seq.empty()
    Seq<Int> b = Seq.empty<Int>()
    Seq<Int> c = makeEmpty()
    Holder h = new Holder()
    List<String> words = ["a", "b"]
    Seq<String> w = Seq.of(words)
    print(a.length())
    print(s.length())
    print(b.length())
    print(c.length())
    print(h.items.length())
    print(a.zip(w).length())
    Seq<String> chain = a.map((Int v) -> str(v)).map((String x) -> x + "!")
    print(chain.length())
    return 0
}
