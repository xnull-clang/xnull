package interp

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// det01Src 覆盖当前解释器全部会产出文本的路径：Map keys()（有序键）、数组遍历、
// 类与 self 字段、Result、字符串插值——用于验证「同一源程序 → 相同运行结果」。
const det01Src = `
class Node {
    Int id = 0

    Int bump(Int v) {
        self.id = self.id + v
        return self.id
    }
}

static Int main() {
    Map<String, Int> m = ["b": 2, "a": 1, "c": 3]
    m.put("d", 4)
    for k in m.keys() {
        print(k)
        print(str(m.getOr(k, 0)))
    }
    Int[] xs = [1, 2, 3]
    Int total = 0
    for v in xs {
        total = total + v
    }
    print(str(total))
    Node n = new Node()
    print(str(n.bump(9)))
    Result<Int, String> r = Ok(5)
    print("ok=" + str(r.isOk()) + " v=" + str(r.value()))
    return 3
}
`

// TestDET01RuntimeStable —— 台账 DET-01 验收要点第 2 项：
// 同一源程序、同一实现版本、同一选项产生相同运行结果。
// 判定：stdout 与退出码在 10 轮内逐字节一致。
func TestDET01RuntimeStable(t *testing.T) {
	u, diags := xfront.ParseUnit("det01.x", det01Src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	run := func() (string, int) {
		var out strings.Builder
		code, _ := Run(u, &out, nil)
		return out.String(), code
	}
	firstOut, firstCode := run()
	if strings.TrimSpace(firstOut) == "" {
		t.Fatal("期望有输出（本用例用于验证运行结果稳定性）")
	}
	if firstCode != 3 {
		t.Fatalf("退出码 %d，期望 3（Int main 返回值原样透传）：%q", firstCode, firstOut)
	}
	for round := 1; round <= 10; round++ {
		out, code := run()
		if out != firstOut || code != firstCode {
			t.Fatalf("第 %d 轮运行结果与首轮不一致（DET-01 违约）：\n--- 首轮 rc=%d ---\n%s\n--- 本轮 rc=%d ---\n%s",
				round, firstCode, firstOut, code, out)
		}
	}
}
