class Node {
    Int v = 0
}
static Int main() {
    Node a = new Node()
    a.v = 1
    if true {
        a = new Node()
        a.v = 2
    }
    Int i = 0
    List<String> xs = []
    while i < 50000 {
        xs.push("x" + str(i))
        i = i + 1
    }
    print(str(a.v))
    return 0
}
