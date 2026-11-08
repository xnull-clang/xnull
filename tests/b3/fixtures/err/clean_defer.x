static Int main() {
    print("A")
    defer print("cleanup 1")
    defer print("cleanup 2")
    print("B")
    return 0
}
