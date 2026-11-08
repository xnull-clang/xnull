static Int main() {
    print("A")
    if true {
        print("B")
        defer print("inner")
        print("C")
    }
    print("D")
    return 0
}
