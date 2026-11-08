class Res {
    Int v = 1

    void deinit() {
        print("bye")
    }
}

static Int main() {
    Res r = new Res()
    print(r.v)
    return 0
}
