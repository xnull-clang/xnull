class Box<T> {
    T value
    Box(T v) { self.value = v }
}
class PairBox<T> {
    Box<T> box
    PairBox(Box<T> b) { self.box = b }
}
static Int main() {
    PairBox<Int> p = new PairBox<Int>(new Box<Int>(7))
    print(p.box.value)
    return 0
}
