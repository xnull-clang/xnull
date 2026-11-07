protocol P {
    Int f();
}
class Val {
    Int x = 7;
    Int f() { return x }
}
class Ref implements P {
    P? peer = null;
    Int x = 7;
    Int f() { return x }
}
static Int main() {
    Val v = new Val()
    Ref r = new Ref()
    print(v.f())
    print(r.f())
    return 0
}
