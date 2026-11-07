class C { Result<Int, String> r = Ok(5); }
static Int main() {
    C c = new C()
    print(c.r.unwrapOr(0))
    return 0
}
