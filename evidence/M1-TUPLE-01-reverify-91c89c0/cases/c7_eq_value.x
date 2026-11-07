static Int main() {
    (Int, String) a = (1, "x" + "y")
    (Int, String) b = (1, "x" + "y")
    print(a == b)
    print(a === b)
    print(a != b)
    print(a !== b)
    (Int, Int) c = (1, 2)
    (Int, Int) d = (1, 2)
    print(c === d)
    print(c)
    return 0
}
