static T identity<T>(T value) {
    return value
}

static A pickFirst<A, B>(A first, B second) {
    return first
}

static B pickSecond<A, B>(A first, B second) {
    return second
}

class Box<T> {
    T value
    Box(T v) { self.value = v }
    T get() { return self.value }
}

class Pair<A, B> {
    A left
    B right
    Pair(A a, B b) {
        self.left = a
        self.right = b
    }
    A getLeft() { return self.left }
    B getRight() { return self.right }
}

static Int main() {
    print(identity<Int>(7))
    print(identity<String>("generic"))
    Box<Int> b = new Box<Int>(9)
    Box<String> s = new Box<String>("boxed")
    print(b.get())
    print(s.get())
    print(pickFirst(11, "inferred"))
    print(pickSecond(12, "second"))
    Pair<Int, String> p = new Pair<Int, String>(21, "nested")
    print(p.getLeft())
    print(p.getRight())
    Box<Pair<Int, String>> nested = new Box<Pair<Int, String>>(p)
    print(nested.get().getLeft())
    return 0
}
