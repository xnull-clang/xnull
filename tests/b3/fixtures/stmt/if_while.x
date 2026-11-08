static Int main() {
    Int s = 0
    Int i = 0
    while i < 3 {
        s += i
        i = i + 1
    }
    if s > 0 {
        print(s)
    } else {
        print(0)
    }
    return 0
}
