enum Color { Red, Green }
static Int main() {
    Color c = Color.Red
    switch c {
        case Color.Red:
            print("r")
        default:
            print("d")
        default:
            print("d2")
    }
    return 0
}
