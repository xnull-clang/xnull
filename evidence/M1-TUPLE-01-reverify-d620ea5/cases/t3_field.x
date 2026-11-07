class Holder {
    (Int, Int) p = (1, 2)
    (Int, Int) zero
    (Int, String)? opt = null
    List<(Int, Int)> xs = [(1, 2), (3, 4)]
}
static Int main() {
    Holder h = new Holder()
    print(h.p.0)
    print(h.p.1)
    print(h.zero.0)
    print(h.zero.1)
    print(h.opt?.0 == null)
    print(h.xs.get(0).0)
    print(h.xs.get(1).1)
    (Int, Int) copy = h.p
    copy.0 = 9
    print(h.p.0)
    h.p.0 = 5
    print(h.p.0)
    return 0
}
