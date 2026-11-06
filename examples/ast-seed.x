// 自举素材 #2（M5.1-b）：AST 节点表示与求值器。
// 单类 Node（Int kind + String text + Int num + List<Node> kids）承载表达式树；
// sumKind/eval 演示递归遍历（自引用字段 + 递归方法调用），dump 输出 S 表达式形态。
// 覆盖：类字段为 List<类> 与类引用、for-in 字段链、递归顶层函数、String 成员。

class Node {
    Int kind = 0;
    String text = "";
    Int num = 0;
    List<Node> kids = [];
}

static Node mkNum(Int n) {
    Node t = new Node();
    t.kind = 1;
    t.num = n;
    return t;
}

static Node mkOp(String op, Node l, Node r) {
    Node t = new Node();
    t.kind = 2;
    t.text = op;
    t.kids.push(l);
    t.kids.push(r);
    return t;
}

// eval：+ - * / 二元求值（叶子取 num）。
static Int eval(Node n) {
    if (n.kind == 1) {
        return n.num;
    }
    Int l = eval(n.kids.get(0));
    Int r = eval(n.kids.get(1));
    if (n.text == "+") {
        return l + r;
    }
    if (n.text == "-") {
        return l - r;
    }
    if (n.text == "*") {
        return l * r;
    }
    return l / r;
}

// dump：S 表达式形态（叶子输出数字）。
static String dump(Node n) {
    if (n.kind == 1) {
        return str(n.num);
    }
    return "(" + n.text + " " + dump(n.kids.get(0)) + " " + dump(n.kids.get(1)) + ")";
}

// nodeCount：递归计数（演示递归 + 字段链 for-in）。
static Int nodeCount(Node n) {
    Int t = 1;
    for k in n.kids {
        t = t + nodeCount(k);
    }
    return t;
}

static Int main() {
    // (1 + 2) * 3 → 9
    Node e = mkOp("*", mkOp("+", mkNum(1), mkNum(2)), mkNum(3));
    print(dump(e));
    print(eval(e));
    print(nodeCount(e));
    // (10 - 4) / 2 → 3
    Node f = mkOp("/", mkOp("-", mkNum(10), mkNum(4)), mkNum(2));
    print(dump(f));
    print(eval(f));
    return 0;
}
