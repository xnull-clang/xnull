class C {
    @ReadOnly Int x = 1;
    Int bump() { x = 2; return x }
}
static Int main() {
    C c = new C()
    print(c.bump())
    c.x = 3
    print(c.x)
    return 0
}
