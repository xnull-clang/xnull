class Holder {
    List<Int> xs = [1, 2, 3];
}
static Int main() {
    Holder h = new Holder()
    h.xs.clear()
    print(h.xs.length())
    return 0
}
