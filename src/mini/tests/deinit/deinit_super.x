package app

class Base {
    deinit() {
        print("base")
    }
}

class Derived : Base {
    deinit() {
        print("derived")
        super.deinit()
    }
}

static Int main() {
    Derived d = new Derived()
    print("main")
    return 0
}
