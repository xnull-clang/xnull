class A {
    Int x = 1;
    A(Int v) { self.x = v }
    Int get() { return x }
    void inc() { x = x + 1 }
}
static Int main() {
    A a = new A(7)
    print(a.get())
    a.inc()
    print(a.get())
    return 0
}
