static Int mark(Int v) {
    print("init " + str(v))
    return v
}
Int a = mark(1)
Int b = mark(a + 1)
static Int main() {
    print("main " + str(b))
    return 0
}
