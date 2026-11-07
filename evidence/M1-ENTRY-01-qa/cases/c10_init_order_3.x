static Int mark(Int v) {
    print("m" + str(v))
    return v
}
Int a = mark(10)
Int b = mark(a + 10)
String s = "s"
Int c = mark(b + 10)
static Int main() {
    print("main " + str(a) + "," + str(b) + "," + str(c) + "," + s)
    return 0
}
