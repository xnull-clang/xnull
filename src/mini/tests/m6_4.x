enum Color {
    Red,
    Green,
    Blue
}

struct Point {
    Int x = 0;
    Int y = 0;

    Int sum() {
        return self.x + self.y;
    }
}

protocol Named {
    String name();
}

class Item implements Named {
    String label = "item";

    String name() {
        return self.label;
    }
}

static Int main() {
    Point p = new Point();
    p.x = 3;
    p.y = 4;
    print(p.sum());

    Color c = Color.Green;
    print(c == Color.Green);
    print(c == Color.Red);

    Item it = new Item();
    print(it.name());

    Set<Int> s = Set.of(1, 2, 2, 3);
    print(s.length());
    print(s.has(2));
    return 0;
}
