static Int main() {
    Int[] a = [1, 2]
    String res = ""
    Int i = 0
    while i < a.length() {
        if i > 0 {
            res = res + "-"
        }
        res = res + str(a[i])
        i = i + 1
    }
    print(res)
    return 0
}
