class C {
    private Int a = 1;
    protected Int b = 2;
    public Int c = 3;

    private Int pa() { return _a }
    protected Int pb() { return b }
    public Int pc() { return c }

    Int all() { return _a + b + c + pa() + pb() + pc() }
}
static Int main() {
    C x = new C()
    print(x.all())
    print(x.pc())
    print(x.c)
    return 0
}
