protocol Shape {
    Int area()
}

class Square implements Shape {
    Int side = 0

    Square(Int s) {
        self.side = s
    }

    Int area() {
        return self.side * self.side
    }
}

static Int main() {
    Shape s = new Square(3)
    print(s.area())
    return 0
}
