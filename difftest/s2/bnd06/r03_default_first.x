enum Color { Red, Green, Blue }
static Int main() {
    Color c = Color.Red
    switch c {
        default:
            print("d")
        case Color.Red:
            print("r")
    }
    return 0
}
