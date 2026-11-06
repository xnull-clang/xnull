class Node {
    Int v = 0;
}

static Int sumAll(List<Node> xs) {
    Int t = 0;
    for n in xs {
        t = t + n.v;
    }
    return t;
}

static Int main() {
    List<Node> xs = [];
    Node a = new Node();
    a.v = 5;
    xs.push(a);
    Node b = new Node();
    b.v = 7;
    xs.push(b);
    print(sumAll(xs));
    print(xs.length());
    return 0;
}
