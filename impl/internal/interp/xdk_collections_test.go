package interp

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// S6-07：collections 源码单元解释执行（算法 + 4 容器）。
func TestXdkCollectionsRuntime(t *testing.T) {
	path, err := filepath.Abs(filepath.Join("..", "..", "lib", "xdk", "collections.x"))
	if err != nil {
		t.Fatal(err)
	}
	src, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("读取 collections.x 失败：%v", err)
	}
	main := `
static Int main() {
    List<Int> xs = [3, 1, 2]
    sortBy<Int>(xs, (Int a, Int b) -> a < b)
    print(xs.get(0))
    List<Int> d = dedup<Int>([1, 2, 1, 3], (Int a, Int b) -> a == b)
    print(d.length())
    Int? f = find<Int>(xs, (Int a) -> a == 2)
    print(f)
    Map<Int, List<Int>> g = groupByInt<Int>([1, 2, 3, 4], (Int x) -> x % 2)
    print(g.getOr(0, []).length())
    print(g.getOr(1, []).length())

    RingBuffer<Int> rb = new RingBuffer<Int>(2)
    print(rb.push(1))
    print(rb.push(2))
    print(rb.push(3))
    print(rb.pop())
    print(rb.pop())

    OrderedMap<Int> om = new OrderedMap<Int>()
    om.put(2, 20)
    om.put(1, 10)
    print(om.get(1))
    print(om.length())

    BTreeMap<Int> bt = new BTreeMap<Int>()
    bt.put(3, 30)
    bt.put(1, 10)
    bt.put(2, 20)
    Int[] ks = bt.keysArray()
    print(ks[0])
    print(ks[2])
    print(bt.getOr(2, 0))

    PriorityQueue<Int> pq = new PriorityQueue<Int>((Int a, Int b) -> a < b)
    pq.push(3)
    pq.push(1)
    pq.push(2)
    print(pq.pop())
    print(pq.pop())
    print(pq.pop())
    return 0
}
`
	u, diags := xfront.ParseUnit(path, string(src)+main)
	if len(diags) > 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	var out strings.Builder
	code, err := Run(u, &out, nil)
	want := "1\n3\n2\n2\n2\ntrue\ntrue\nfalse\n1\n2\n10\n2\n1\n3\n20\n1\n2\n3\n"
	if err != nil || code != 0 || out.String() != want {
		t.Fatalf("out=%q want=%q code=%d err=%v", out.String(), want, code, err)
	}
}
