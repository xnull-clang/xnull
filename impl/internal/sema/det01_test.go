package sema

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// renderDiags 解析并分析同一源程序，把诊断按输出顺序渲染成文本。
func renderDiags(t *testing.T, src string) string {
	t.Helper()
	u, pd := xfront.ParseUnit("t.x", src)
	if len(pd) != 0 {
		t.Fatalf("解析诊断不应出现：%v", pd)
	}
	_, sd := AnalyzeWith("t.x", u)
	var b strings.Builder
	for _, d := range sd {
		b.WriteString(d.String())
		b.WriteString("\n")
	}
	return b.String()
}

// TestDET01DiagStableAcrossRuns —— 台账 DET-01 验收要点第 1 项：
// 同一源程序、同一实现版本、同一选项产生相同诊断。
// 判定：同一源连续分析 200 轮，诊断文本与顺序逐字节一致。
func TestDET01DiagStableAcrossRuns(t *testing.T) {
	src := `
class Holder {
    private Int _x = 0
    private Int _y = 0

    void touch(Int _x) {
        print(_x)
    }
}

static Int main() {
    Int a = firstUndefined
    Int b = secondUndefined
    Holder h = new Holder()
    h._y = 1
    return 0
}
`
	first := renderDiags(t, src)
	if strings.Count(first, "error[") < 3 {
		t.Fatalf("期望至少 3 条诊断（本用例用于验证多条诊断的顺序稳定性），实际：\n%s", first)
	}
	for round := 1; round <= 200; round++ {
		if got := renderDiags(t, src); got != first {
			t.Fatalf("第 %d 轮诊断与首轮不一致（DET-01 违约）\n--- 首轮 ---\n%s\n--- 本轮 ---\n%s", round, first, got)
		}
	}
}

// TestDET01DiagIndependentOfMapOrder —— 台账 DET-01 验收要点第 1 项的实现约束：
// 诊断顺序不得依赖 Go map 迭代序（map 迭代序是随机源）。
// 构造方式：临时注册两个导出同名符号的 XDK 包，使 RES-104 歧义诊断多条同时产生；
// 若发射顺序取自 map 迭代，则 200 轮内必然出现顺序翻转。
func TestDET01DiagIndependentOfMapOrder(t *testing.T) {
	old := xdkPackages
	xdkPackages = map[string]map[string]bool{
		"alpha": {"SharedOne": true, "SharedTwo": true},
		"beta":  {"SharedOne": true, "SharedTwo": true},
	}
	defer func() { xdkPackages = old }()

	src := "import xdk.alpha\nimport xdk.beta\n\nstatic Int main() {\n    return 0\n}\n"
	first := renderDiags(t, src)
	if got := strings.Count(first, "RES-104"); got != 2 {
		t.Fatalf("期望 2 条 RES-104 歧义诊断（SharedOne/SharedTwo），实际 %d 条：\n%s", got, first)
	}
	for round := 1; round <= 200; round++ {
		if got := renderDiags(t, src); got != first {
			t.Fatalf("第 %d 轮歧义诊断顺序与首轮不一致（诊断顺序依赖 map 迭代序，DET-01 违约）\n--- 首轮 ---\n%s\n--- 本轮 ---\n%s", round, first, got)
		}
	}
}
