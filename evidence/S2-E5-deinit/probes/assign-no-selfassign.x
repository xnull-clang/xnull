class A {
    void deinit() {
        print("A-deinit")
    }
}

class H {
    A a
}

static Int main() {
    H h = new H()
    A a1 = new A()
    h.a = a1
    print("assigned")
    A a2 = new A()
    h.a = a2
    print("reassigned")
    print("selfassign")
    return 0
}
