class Box {
    String? s = null;
}

static Int main() {
    Box b = new Box()
    print(b.s ?? "fallback")
    b.s = "ok"
    print(b.s ?? "fallback")
    return 0
}
