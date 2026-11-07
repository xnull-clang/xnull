struct Point {
    Int x = 0;
    Int y = 0;
}
static Int copyOf(Point p) { p.x = 9; return p.x }
static Point make(Int v) {
    Point p = new Point()
    p.x = v
    p.y = v + 1
    return p
}
static Int main() {
    Point a = new Point()
    a.x = 1
    a.y = 2
    Point b = a
    b.x = 10
    print(a.x)
    print(b.x)
    print(copyOf(a))
    print(a.x)
    Point c = make(3)
    c.x = 30
    print(c.x)
    print(c.y)
    return 0
}
