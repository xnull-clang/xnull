static Int main() {
    (Int, String) a = (1, "x")
    (Int, String) b = (1, "x")
    print(a == b)
    print(a != b)
    print(a === a)
    print(a !== b)
    print($"v={a}")
    return 0
}
