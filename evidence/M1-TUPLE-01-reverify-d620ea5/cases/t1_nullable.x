static Int main() {
    (Int, Int)? o = null
    (Int, String)? v = (5, "a")
    print(o?.0 == null)
    print(v?.0)
    print(v?.1)
    return 0
}
