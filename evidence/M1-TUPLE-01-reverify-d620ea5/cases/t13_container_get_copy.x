static Int main() {
    List<(Int, Int)> l = [(1, 2)]
    (Int, Int) x = l.get(0)
    x.0 = 9
    print(l.get(0).0)
    (Int, Int)[] a = [(3, 4)]
    (Int, Int) y = a[0]
    y.1 = 8
    print(a[0].1)
    return 0
}
