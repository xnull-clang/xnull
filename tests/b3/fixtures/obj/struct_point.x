struct Pair {
    Int a = 0
    Int b = 0

    Pair(Int x, Int y) {
        self.a = x
        self.b = y
    }

    Int sum() {
        return self.a + self.b
    }
}

static Int main() {
    Pair p = new Pair(1, 2)
    Pair q = p
    q.a = 9
    print(p.sum())
    print(q.sum())
    return 0
}
