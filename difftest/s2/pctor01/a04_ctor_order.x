class C {
    Int x = 1;
    C() { print(x); x = 2 }
}
static Int main() {
    C c = new C()
    print(c.x)
    return 0
}
