class Node {
    List<Node> next;
    void deinit() { print("dN") }
}
static Int main() {
    Node a = new Node()
    a.next = [a]
    print("main")
    return 0
}
