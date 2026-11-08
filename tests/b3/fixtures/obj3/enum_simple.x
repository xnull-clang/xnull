enum Color { Red, Green, Blue }
static Int main() {
    Color c = Color.Green
    print(c)
    switch (c) {
        case Color.Red: print("r")
        case Color.Green: print("g")
        case Color.Blue: print("b")
    }
    return 0
}
