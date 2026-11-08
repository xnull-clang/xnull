static T identity<T>(T value) {
    return value
}
static Int main() {
    print(identity<Int>(7))
    print(identity<String>("s"))
    return 0
}
