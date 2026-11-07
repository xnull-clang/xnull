static Int main() {
    Set<Int> s = [7, 8]
    Int idx = 0
    Int val = 0
    for x in s {
        if idx == 0 {
            val = x
            break
        }
        idx = idx + 1
    }
    print(val)
    return 0
}
