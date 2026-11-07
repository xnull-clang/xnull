enum Color { Red, Green, Blue }
class Holder {
    Color c;
    String name() {
        switch c {
            case Color.Red: return "r"
            case Color.Green: return "g"
            case Color.Blue: return "b"
        }
        return "?"
    }
}
static Int main() {
    Holder h = new Holder()
    h.c = Color.Green
    print(h.name())
    h.c = Color.Blue
    print(h.name())
    return 0
}
