class B {
    protected Int x = 7;
}
class D : B {
    Int g(B other) { return other.x }
}
static Int main() { return 0 }
