struct S {
    Int v = 0;
    Int delayed() {
        var f = () -> { return self.v; };
        return f();
    }
}
static Int main() { return 0 }
