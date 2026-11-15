static T identity<T>(T value) {
    return value
}

class Box<T> {
    T value
    Box(T v) { self.value = v }
    T get() { return self.value }
}

static Int main() {
    print(identity<Int>(7))
    print(identity<String>("generic"))
    Box<Int> b = new Box<Int>(9)
    Box<String> s = new Box<String>("boxed")
    print(b.get())
    print(s.get())
    return 0
}
