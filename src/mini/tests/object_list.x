class Node {
    String name
    Node(String n) { self.name = n }
}

static Int main() {
    List<Node> ns = []
    ns.push(new Node("a"))
    ns.push(new Node("b"))
    print(ns.length())
    print(ns.get(1).name)

    List<String> ss = ["x", "y"]
    print(ss.join(","))
    print(ss.get(0).startsWith("x"))

    String raw = "a,b"
    List<String> parts = raw.split(",")
    print(parts.length())
    print(parts.get(1))
    return 0
}
