static Int main() {
    (Int, Int) t = (1, 2)
    List<(Int, Int)> xs = [t]
    t.0 = 9
    print(xs.get(0).0)
    (Int, Int) a = (3, 4)
    (Int, Int) b = a
    b.1 = 8
    print(a.1)
    print(b.1)
    return 0
}
