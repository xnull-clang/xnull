class Animal {
    Int legs = 4

    Int count() {
        return self.legs
    }
}

class Bird : Animal {
    Int wings = 2

    Int total() {
        return count() + wings
    }
}

static Int main() {
    Bird b = new Bird()
    print(b.count())
    print(b.total())
    return 0
}
