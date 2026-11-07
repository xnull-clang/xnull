class Helper {
    String name = "helper"
    void deinit() { print("helper-deinit") }
}
class Node {
    Node next;
    Helper h;
    void deinit() { print("node-deinit " + self.h.name) }
}
static Int main() {
    Node a = new Node()
    Node b = new Node()
    a.next = b
    b.next = a
    a.h = new Helper()
    b.h = new Helper()
    print("main")
    return 0
}
