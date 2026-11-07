struct Pair<A, B> {
    A a;
    B b;
}
struct Holder {
    Pair<Int, Int> p;
}
static Int main() {
    Pair<Int, Int> q = new Pair<Int, Int>()
    q.a = 1
    q.b = 2
    print(q.a)
    print(q.b)
    Holder h = new Holder()
    h.p = q
    h.p.a = 7
    print(q.a)
    print(h.p.a)
    return 0
}
