struct Cell<T> {
    T v;
}
static Int main() {
    Cell<Int> c = new Cell<Int>()
    c.v = 4
    print(c.v)
    return 0
}
