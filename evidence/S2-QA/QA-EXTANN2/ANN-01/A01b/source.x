@annotation A { final Int x = 0; }
class C {
    @A C() { }
    @A void deinit() { }
}
static Int main() {
    C c = new C()
    return 0
}
