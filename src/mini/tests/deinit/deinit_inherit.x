package app

class Base {
    deinit() {
        print("base")
    }
}

class Derived : Base {
    deinit() {
        print("derived")
    }
}

static Int main() {
    Derived d = new Derived()
    print("main")
    return 0
}
