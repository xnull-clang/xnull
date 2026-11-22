@Data
class User {
    String name
    Int age
    User(String name0, Int age0) {
        self.name = name0
        self.age = age0
    }
}

@Value
class Point {
    final Int x
    final Int y
    Point(Int x0, Int y0) {
        self.x = x0
        self.y = y0
    }
}

@Copy
class Item {
    String name
    Int count
    Item(String name0, Int count0) {
        self.name = name0
        self.count = count0
    }
}

@Value
class Box<T> {
    final T value
    Box(T value0) { self.value = value0 }
}
static Int main() {
    User a = new User("ann", 3)
    User b = new User("ann", 3)
    User c = new User("bob", 4)
    print(a.equals(b))
    print(a.equals(c))
    print(a.equals(null))
    print(a.toString())
    User d = a.copy()
    a.name = "changed"
    print(d.name)
    print(a.name)

    Point p0 = new Point(1, 2)
    Point p1 = new Point(1, 2)
    Point p2 = new Point(2, 1)
    print(p0.equals(p1))
    print(p0.equals(p2))
    print(p0.toString())
    Point p3 = p0.copy()
    print(p3.x)

    Item i0 = new Item("a", 1)
    Item i1 = i0.withName("b").withCount(2)
    print(i0.name)
    print(i0.count)
    print(i1.name)
    print(i1.count)

    Box<Int> b0 = new Box<Int>(3)
    Box<Int> b1 = new Box<Int>(3)
    print(b0.equals(b1))
    Box<Int> b2 = b0.copy()
    print(b2.value)
    print(b0.toString())
    return 0
}
