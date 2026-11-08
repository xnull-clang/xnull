static T identity<T>(T value) {
    return value
}
static Int main() {
    print(identity<Int>(7))
    return 0
}
