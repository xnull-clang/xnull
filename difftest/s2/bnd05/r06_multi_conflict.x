protocol A {
    Bool f();
}
protocol B {
    Int f();
}
class C implements A, B {
    Bool f() { return true }
}
static Int main() { return 0 }
