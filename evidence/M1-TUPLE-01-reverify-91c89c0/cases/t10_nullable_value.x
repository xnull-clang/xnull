static Int main() {
    (Int, Int)? o = (1, 2)
    Int? x = o?.0
    print(x == null)
    print(x)
    (Int, Int)? n = null
    Int? y = n?.0
    print(y == null)
    return 0
}
