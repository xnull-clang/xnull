@Value
class Box<T> {
    final T value
    Box(T value0) { self.value = value0 }
}
static Int main() {
    Box<Int> a = new Box<Int>(3)
    Box<Int> b = new Box<Int>(3)
    print(a.equals(b))
    Box<Int> c = a.copy()
    print(c.value)
    print(a.toString())
    return 0
}
