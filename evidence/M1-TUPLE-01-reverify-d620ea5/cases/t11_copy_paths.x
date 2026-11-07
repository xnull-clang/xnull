static void mutate((Int, Int) x) { x.0 = 99 }
static (Int, Int) ret((Int, Int) x) { return x }
static Int main() {
    (Int, Int) t = (1, 2)
    List<(Int, Int)> l = [t]
    t.0 = 9
    print(l.get(0).0)
    List<(Int, Int)> p = []
    p.push(t)
    t.0 = 8
    print(p.get(0).0)
    (Int, Int)[] a = [t]
    t.0 = 7
    print(a[0].0)
    (Int, Int) c = t
    c.0 = 6
    print(t.0)
    mutate(t)
    print(t.0)
    (Int, Int) r = ret(t)
    t.0 = 5
    print(r.0)
    return 0
}
