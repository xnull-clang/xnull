class V { Int x = 1; }
static V make() {
    V v = new V()
    v.x = 7
    return v
}
static Int main() {
    V v = make()
    print(v.x)
    return 0
}
