protocol P {
    Int f();
}
class A implements P {
    Int f() { return 1 }
}
class B implements P {
    Int f() { return 2 }
}
static Int main() {
    P p = new B()
    print(p.f())
    P q = new A()
    print(q.f())
    return 0
}
