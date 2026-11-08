static Int main() {
    (Int, Int) t = (1, 2)
    List<(Int, Int)> l = [t]
    print(l.get(0).0)
    print(l.get(0).1)
    return 0
}
