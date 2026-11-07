enum Color { Red, Green, Blue }
static Int main() {
    Color c = Color.Red
    switch c {
        case Color.Red:
            print("r")
        case Color.Green:
            print("g")
        case Color.Blue:
            print("b")
        default:
            print("d")
    }
    return 0
}
