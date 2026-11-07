package interp

import "testing"

// T3/T6：元素访问、元素赋值、==/!=/===/!==、插值。
func TestTupleElementAssignmentAndEquality(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    (Int, Int) a = (1, 2)
    (Int, Int) b = a
    b.0 = 9
    print(a.0)
    print(b.0)

    (Int, String) x = (1, "x")
    (Int, String) y = (1, "x")
    print(x == y)
    print(x != y)
    print(x === y)
    print(x !== y)
    print($"v={x}")
    return 0
}`)
	want := "1\n9\ntrue\nfalse\ntrue\nfalse\nv=(1, x)\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// T4：var 推断元组；嵌套元组访问。
func TestTupleInferenceAndNested(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    var inferred = (1, "a")
    print(inferred.0)
    print(inferred.1)

    ((Int, String), Bool) nested = ((2, "b"), true)
    (Int, String) inner = nested.0
    print(inner.0)
    print(inner.1)
    print(nested.1)
    return 0
}`)
	want := "1\na\n2\nb\ntrue\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// T3：可空元组 `?.N`；非 null 时返回元素。
func TestTupleNullSafeElement(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    (Int, String) pair = (7, "a")
    print(pair?.0)
    return 0
}`)
	if err != nil || out != "7\n" {
		t.Fatalf("out=%q err=%v", out, err)
	}
}

// TUPLE-01 类型位置运行时：顶层返回、可空元组 `?.` null 分支、类字段、容器元素。
func TestTupleTypePositionsRuntime(t *testing.T) {
	out, err := runSrc(t, `
static (Int, Int) top = (11, 12)
static (Int, String)? topOpt = null
static (Int, Int) make() {
    return (1, 2)
}
static (Int, Int)? none() {
    return null
}
static List<(Int, Int)> all() {
    return [(6, 7)]
}
class Holder {
    (Int, Int) p = (1, 2)
    (Int, Int) zero
    (Int, String)? opt = null
    List<(Int, Int)> xs = [(1, 2), (3, 4)]
}
static Int main() {
    print(top.0)
    print(top.1)
    print(topOpt == null)
    print(make().0)
    print(make().1)
    print(none() == null)

    (Int, Int)? o = null
    (Int, String)? v = (5, "a")
    print(o?.0 == null)
    print(v?.0)
    print(v?.1)

    Holder h = new Holder()
    print(h.p.0)
    print(h.p.1)
    print(h.zero.0)
    print(h.zero.1)
    print(h.opt?.0 == null)
    print(h.xs.get(0).0)
    print(h.xs.get(1).1)

    List<(Int, Int)> xs = [(7, 8)]
    print(xs.get(0).0)
    print(all().get(0).1)
    (Int, Int)[] arr = [(9, 10)]
    print(arr[0].1)
    (Int, Int)[] fixed = new (Int, Int)[2]
    print(fixed[0].0)
    print(fixed[0].1)
    return 0
}`)
	want := "11\n12\ntrue\n1\n2\ntrue\ntrue\n5\na\n1\n2\n0\n0\ntrue\n1\n4\n7\n7\n10\n0\n0\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// TUPLE-01 类字段值语义：字段元组按值复制，副本修改不影响字段。
func TestTupleClassFieldCopy(t *testing.T) {
	out, err := runSrc(t, `
class Holder {
    (Int, Int) p = (1, 2)
}
static Int main() {
    Holder h = new Holder()
    (Int, Int) copy = h.p
    copy.0 = 9
    print(h.p.0)
    print(copy.0)
    h.p.0 = 5
    print(h.p.0)
    return 0
}`)
	want := "1\n9\n5\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// §2.11 值语义：存入容器（数组/List/Map 字面量与 push/insert/set/put）复制整个元组；
// 引用元素只复制句柄。
func TestTupleContainerCopy(t *testing.T) {
	out, err := runSrc(t, `
class Box { Int v = 0; }
static Int main() {
    (Int, Int) t = (1, 2)
    (Int, Int)[] arr = [t]
    t.0 = 9
    print(arr[0].0)
    arr[0].1 = 8
    print(t.1)

    List<(Int, Int)> xs = [t]
    xs.push(t)
    t.0 = 5
    print(xs.get(0).0)
    print(xs.get(1).0)
    xs.set(0, t)
    t.0 = 6
    print(xs.get(0).0)
    xs.insert(0, t)
    t.0 = 7
    print(xs.get(0).0)

    arr[0] = t
    xs[0] = t
    t.0 = 70
    print(arr[0].0)
    print(xs[0].0)

    Map<String, (Int, Int)> m = ["a": t]
    m.put("b", t)
    t.0 = 8
    (Int, Int)? a = m.get("a")
    (Int, Int)? b = m.get("b")
    print(a?.0)
    print(b?.0)

    (Int, Int)[] fixed = new (Int, Int)[2]
    fixed[0].0 = 3
    print(fixed[1].0)

    ((Int, Int), Int) nested = (t, 1)
    t.0 = 4
    print((nested.0).0)

    Box box = new Box()
    (Box, Int) bt = (box, 1)
    List<(Box, Int)> bs = [bt]
    box.v = 42
    (Box, Int) got = bs.get(0)
    print(got.0.v)
    return 0
}`)
	want := "1\n2\n9\n9\n5\n6\n7\n7\n70\n70\n0\n8\n42\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}
