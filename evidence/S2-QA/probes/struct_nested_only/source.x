struct Inner { Int v = 1; }
struct Outer { Inner inner = new Inner(); }
static Int main() {
    Outer o = new Outer()
    print(o.inner.v)
    return 0
}
