static Int main() {
    (Int, String) a = (1, "x" + "y")
    (Int, String) b = (1, "x" + "y")
    print(a == b)
    print(a === b)
    Int[] arr = [1, 2]
    (Int[], Int) p = (arr, 1)
    (Int[], Int) q = (arr, 1)
    print(p === q)
    Int[] arr2 = [1, 2]
    (Int[], Int) r = (arr2, 1)
    print(p === r)
    return 0
}
