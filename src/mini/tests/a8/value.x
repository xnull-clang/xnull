@Value
class Point {
    final Int x
    final Int y
    Point(Int x0, Int y0) {
        self.x = x0
        self.y = y0
    }
}
static Int main() {
    Point a = new Point(1, 2)
    Point b = new Point(1, 2)
    Point c = new Point(2, 1)
    print(a.equals(b))
    print(a.equals(c))
    print(a.toString())
    Point d = a.copy()
    print(d.x)
    return 0
}
