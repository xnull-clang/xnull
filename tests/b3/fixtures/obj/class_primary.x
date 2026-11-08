class Vec(final Int x, final Int y) {
    Int sum() {
        return x + y
    }
}

static Int main() {
    Vec v = new Vec(4, 5)
    print(v.sum())
    return 0
}
