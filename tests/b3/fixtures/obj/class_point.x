class Point {
    Int x = 0
    Int y = 0

    Point(Int a, Int b) {
        self.x = a
        self.y = b
    }

    Int sum() {
        return self.x + self.y
    }
}

static Int main() {
    Point p = new Point(2, 3)
    print(p.sum())
    return 0
}
