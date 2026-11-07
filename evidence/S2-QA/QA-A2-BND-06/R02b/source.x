enum Color { Red, Green, Blue }
enum Other { X, Y }
static Int main() {
    Color c = Color.Red
    switch c {
        case Color.Red:
            print("r")
        case Color.Green:
            print("g")
        case Color.Blue:
            print("b")
        case Other.X:
            print("x")
    }
    return 0
}
