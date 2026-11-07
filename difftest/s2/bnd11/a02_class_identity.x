class C {
    Int x = 1;
}
static Int main() {
    C a = new C()
    C b = a
    C c = new C()
    print(a === b)
    print(a === c)
    print(a == b)
    return 0
}
