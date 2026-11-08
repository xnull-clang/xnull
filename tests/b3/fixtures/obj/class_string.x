class Named {
    Int id = 0
    String name = "x"

    Named(Int i, String n) {
        self.id = i
        self.name = n
    }

    String label() {
        return self.name
    }
}

static Int main() {
    Named n = new Named(7, "neo")
    print(n.label())
    return 0
}
