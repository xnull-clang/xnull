class Box {
    String tag = ""
    Int v = 0
    Box(Int x) { self.v = x }
    Int get() { return self.v }
}
static Int main() {
    Box b = new Box(1)
    Int i = 0
    while i < 50000 {
        b = new Box(i)
        i = i + 1
    }
    print(str(b.get()))
    return 0
}
