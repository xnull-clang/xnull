package interp

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- M2.4 解释器全量化用例（§2.11 / §6.7 / §7.7 / §9 / §11.2） ----------

// §9.3：T[] 字面量、下标读写、length、join；越界 fatal。
func TestArray(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    Int[] values = [1, 2, 3]
    values[1] = 9
    print(str(values[0]) + str(values[1]) + str(values[2]))
    print(values.length())
    print(values.join("-"))
    return 0
}`)
	want := "193\n3\n1-9-3\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
	// 越界 → fatal → 退出码 134
	_, code, err := runSrcCode(t, "static Int main() {\n    Int[] a = [1]\n    print(a[5])\n    return 0\n}")
	if err == nil || code != 134 {
		t.Fatalf("越界应 fatal 134：code=%d err=%v", code, err)
	}
}

// §9.1：List 可增长容器方法。
func TestList(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    List<Int> xs = [1]
    xs.push(2)
    xs.push(3)
    xs.insert(0, 0)
    xs.set(1, 10)
    print(xs.length())
    print(xs.get(1))
    xs.remove(0)
    print(xs.get(0))
    for x in xs {
        print(x)
    }
    xs.clear()
    print(xs.length())
    return 0
}`)
	want := "4\n10\n10\n10\n2\n3\n0\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// §9.1：Map 方法；keys()/values() 按键排序（DET-01）；Map 不能直接遍历。
func TestMap(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    Map<String, Int> m = ["b": 2, "a": 1]
    m.put("c", 3)
    print(m.length())
    print(m.get("a"))
    print(m.getOr("z", 99))
    print(m.has("b"))
    print(m.keys().join(","))
    print(m.values().join(","))
    print(m.remove("a"))
    print(m.has("a"))
    m.clear()
    print(m.length())
    return 0
}`)
	want := "3\n1\n99\ntrue\na,b,c\n1,2,3\ntrue\nfalse\n0\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
	// Map 直接遍历 → 运行错误
	_, _, err = runSrcCode(t, `
static Int main() {
    Map<String, Int> m = ["a": 1]
    for kv in m {
        print("x")
    }
    return 0
}`)
	if err == nil {
		t.Fatalf("Map 直接遍历应报错")
	}
	// keys() 遍历（确定性顺序）
	out, err = runSrc(t, `
static Int main() {
    Map<String, Int> m = ["c": 3, "a": 1, "b": 2]
    for k in m.keys() {
        print(k)
    }
    return 0
}`)
	want = "a\nb\nc\n"
	if err != nil || out != want {
		t.Fatalf("keys 遍历 out=%q want=%q err=%v", out, want, err)
	}
}

// §9.1：Set 去重；§6.7 Set 遍历。
func TestSet(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    Set<Int> s = [3, 1]
    print(s.add(2))
    print(s.add(1))
    print(s.has(2))
    print(s.length())
    print(s.at(0))
    print(s.remove(3))
    for x in s {
        print(x)
    }
    return 0
}`)
	want := "true\nfalse\ntrue\n3\n3\ntrue\n1\n2\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// §9.2：String 成员方法。
func TestStringMethods(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    String text = "a,b"
    print(text.length())
    print(text.substring(0, 1))
    print(text.indexOf(","))
    print(text.trim().length())
    print(text.split(",").join("|"))
    print(text.replace("a", "x"))
    print(text.toUpper())
    print("abc".startsWith("ab"))
    print("abc".endsWith("c"))
    return 0
}`)
	want := "3\na\n1\n3\na|b\nx,b\nA,B\ntrue\ntrue\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// §2.11：元组字面量、.N 访问、格式化 (a, b)。
func TestTuple(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    (Int, String) pair = (1, "one")
    print(pair.0)
    print(pair.1)
    print(pair)
    return 0
}`)
	want := "1\none\n(1, one)\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// §7.7：闭包值——创建、调用、捕获。
func TestClosure(t *testing.T) {
	out, err := runSrc(t, `
static Int apply(Int(Int, Int) op, Int a, Int b) {
    return op(a, b)
}

static Int apply1(Int(Int) f, Int v) {
    return f(v)
}

static Int triple(Int x) {
    return x * 3
}

static Int main() {
    Int(Int, Int) add = (Int a, Int b) -> {
        return a + b
    }
    print(add(2, 3))
    print(apply(add, 10, 20))
    Int base = 100
    Int(Int) addBase = (Int x) -> base + x
    print(addBase(5))
    print(apply((Int a, Int b) -> a - b, 9, 4))
    print(apply1(triple, 7))
    return 0
}`)
	want := "5\n30\n105\n5\n21\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// §7.7：is / as / as? 运行时判定。
func TestIsAs(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    Any boxed = 42
    print(boxed is Int)
    print(boxed is String)
    print(boxed as Int)
    print((boxed as? String) == null)
    Any s = "hi"
    print(s as String)
    return 0
}`)
	want := "true\nfalse\n42\ntrue\nhi\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
	// as 失败 → fatal
	_, code, err := runSrcCode(t, `
static Int main() {
    Any boxed = 42
    String s = boxed as String
    print(s)
    return 0
}`)
	if err == nil || code != 134 {
		t.Fatalf("as 失败应 fatal 134：code=%d err=%v", code, err)
	}
}

// §11.2：main(args: String[]) 入口第二形态。
func TestMainWithArgs(t *testing.T) {
	u, diags := xfront.ParseUnit("t.x", "static Int main(String[] args) {\n    print(args.length())\n    print(args[0])\n    return 0\n}")
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	var out strings.Builder
	code, err := Run(u, &out, []string{"hello", "world"})
	if err != nil || code != 0 {
		t.Fatalf("code=%d err=%v", code, err)
	}
	if out.String() != "2\nhello\n" {
		t.Fatalf("out=%q", out.String())
	}
}
