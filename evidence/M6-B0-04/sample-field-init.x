class Node {
    Int v = 0;
}
static String mk() {
    return "mk"
}
class C {
    Int a = 1 + 2;
    Bool b = 1 < 2;
    String s = "x" + "y";
    String t = str(42);
    String u = mk();
    List<Int> xs = [1, 2];
    Map<String, Int> m = ["k": 7];
    Set<Int> st = [1, 2, 2];
    Node n2 = new Node();
}
static Int main() {
    C c = new C();
    print(c.a)
    print(c.b)
    print(c.s)
    print(c.t)
    print(c.u)
    print(c.xs.length())
    print(c.xs.get(1))
    print(c.m.getOr("k", 0))
    print(c.st.length())
    print(c.n2.v)
    return 0
}
