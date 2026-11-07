class Inner {
    void deinit() {
        print("inner-deinit")
    }
}

class Outer {
    Inner inner = new Inner()

    void deinit() {
        print("outer-deinit")
    }
}

static Int main() {
    Outer o = new Outer()
    print("main")
    return 0
}
