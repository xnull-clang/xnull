static (Int, Int) swap((Int, Int) p) {
    return (p.1, p.0)
}
static Int main() {
    (Int, Int) t = (3, 4)
    (Int, Int) r = swap(t)
    print(r.0)
    print(r.1)
    return 0
}
