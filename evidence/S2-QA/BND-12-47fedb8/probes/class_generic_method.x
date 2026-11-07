class Util {
    U convert<U>(U value) {
        return value
    }
}
static Int main() {
    Util u = new Util()
    print(u.convert<Int>(5))
    return 0
}
