static Int main() {
    (Int, Int) t = (1, 2)
    print(t.0)
    print(t.1)
    t.0 = 9
    print(t.0 + t.1)
    return 0
}
