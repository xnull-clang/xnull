struct Point {
    Int x = 0;
    Int y = 0;
    Int sum() { return self.x + self.y }
}
static Int main() {
    Point a = new Point()
    a.x = 1
    a.y = 2
    Point b = a
    b.x = 10
    print(a.x)
    print(b.x)
    print(a.sum())
    print(b.sum())
    return 0
}
