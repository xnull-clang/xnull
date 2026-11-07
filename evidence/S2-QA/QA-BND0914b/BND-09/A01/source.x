class Base {
    protected Int x = 1;
    private Int limit = 10;
    Int _retries = 0;

    Int sum() {
        return _limit + _retries + self.x
    }
}
class D : Base {
    Int get() { return self.x }
}
static Int main() {
    D d = new D()
    print(d.sum())
    print(d.get())
    return 0
}
