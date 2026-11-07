static (Int, Int) make() {
    return (1, 2)
}
static (Int, Int)? none() {
    return null
}
static Int main() {
    print(make().0)
    print(make().1)
    print(none() == null)
    return 0
}
