protocol Base { Int base(); }
protocol Child : Base { Int child(); }
class C implements Child {
    Int base() { return 1 }
    Int child() { return 2 }
}
static Int main() {
    C c = new C()
    Child p = c
    Base b = p
    print(b.base())
    print(p.child())
    return 0
}
