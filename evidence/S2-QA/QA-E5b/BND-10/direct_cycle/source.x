class Node {
    Node next;
    void deinit() { print("node-deinit") }
}
static Int main() {
    Node a = new Node()
    Node b = new Node()
    a.next = b
    b.next = a
    print("main")
    return 0
}
