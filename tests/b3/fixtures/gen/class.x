class Box<T> {
    T v;
    Box(T value) { self.v = value }
    T get() { return self.v }
}
static Int main() {
    Box<Int> b = new Box<Int>(9)
    print(b.get())
    return 0
}
