@Copy
class Item {
    String name
    Int count
    Item(String name0, Int count0) {
        self.name = name0
        self.count = count0
    }
}
static Int main() {
    Item a = new Item("a", 1)
    Item b = a.withName("b").withCount(2)
    print(a.name)
    print(a.count)
    print(b.name)
    print(b.count)
    return 0
}
