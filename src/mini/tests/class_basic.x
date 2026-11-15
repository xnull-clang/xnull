class Counter {
    Int n = 0;
    String label = "counter";

    Int add(Int v) {
        self.n = self.n + v;
        return self.n;
    }

    Int get() {
        return self.n;
    }

    String name() {
        return self.label;
    }
}

static Int main() {
    Counter c = new Counter();
    print(c.add(2));
    print(c.get());
    print(c.name());
    return 0;
}
