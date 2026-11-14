package lib.shapes

class Point {
    Int x

    Point(Int x0) {
        self.x = x0
    }

    Int doubled() {
        return scale(self.x)
    }
}
