struct Inner {
    Int v = 1;
}
struct Outer {
    Inner inner = new Inner();
    Int? opt = null;
}
static Int main() {
    Outer o = new Outer()
    print(o.inner.v)
    o.opt = 5
    print(o.opt)
    return 0
}
