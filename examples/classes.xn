// 类与容器（M4.4b）：ARC 对象、字段、方法、容器参数、for-in。
// 完成定义锚点：本示例经编译路径与解释路径输出逐字节一致（stdout/退出码）。

class Tally {
    Int total = 0;
    String label = "tally";

    Int add(Int v) {
        self.total = self.total + v;
        return self.total;
    }

    Int sum(Int[] xs) {
        for v in xs {
            self.total = self.total + v;
        }
        return self.total;
    }

    Int value() {
        return self.total;
    }

    String name() {
        return self.label;
    }
}

static Int main() {
    Tally t = new Tally();
    print(t.value());
    print(t.add(5));
    print(t.value());

    Int[] xs = [1, 2, 3, 4];
    print(t.sum(xs));
    print(t.value());
    print(t.name());

    List<Int> buf = [10, 20];
    buf.push(30);
    print(buf.length());
    print(buf.get(2));

    Map<String, Int> scores = ["amy": 90];
    scores.put("bob", 85);
    print(scores.length());
    print(scores.getOr("bob", 0));

    return 0;
}
