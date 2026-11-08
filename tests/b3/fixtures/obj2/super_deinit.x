class B {
    void deinit() {
        print("dB")
    }
}

class D : B {
    void deinit() {
        print("dD")
        super.deinit()
    }
}

static Int main() {
    D d = new D()
    return 0
}
