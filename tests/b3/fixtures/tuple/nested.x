static Int main() {
    (Int, (Int, Int)) t = (1, (2, 3))
    print(t.0)
    print((t.1).0)
    print((t.1).1)
    return 0
}
