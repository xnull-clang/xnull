static (Int, Int) ret((Int, Int) x) { return x }
static Int main() {
    (Int, Int) t = (1, 2)
    (Int, Int) c = t
    c.0 = 9
    print(t.0)
    (Int, Int) r = ret(t)
    t.0 = 7
    print(r.0)
    return 0
}
