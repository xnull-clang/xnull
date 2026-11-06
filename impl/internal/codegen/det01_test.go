package codegen

import (
	"math/rand"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/interp"
	"xnull.dev/xnull/internal/xfront"
)

// TestDET01InitOrderIndependentOfCreationOrder —— 台账 DET-01 验收要点第 3 项：
// 初始化顺序不依赖文件系统枚举顺序。
// 判定：同一逻辑源码树按 20 种不同的文件创建顺序落盘，合并后的声明序（= 解释器
// 初始化序，§4.3）与运行输出必须逐字节一致，且等于 import 拓扑序。
func TestDET01InitOrderIndependentOfCreationOrder(t *testing.T) {
	files := []struct{ name, src string }{
		{"main.x", "import a\nimport b\n\nstatic Int gMain = 4\n\nstatic Int main() {\n    print(str(gMain) + str(gA) + str(gB) + str(gC))\n    return 0\n}\n"},
		{"a.x", "import c\n\nstatic Int gA = 1\n"},
		{"b.x", "static Int gB = 2\n"},
		{"c.x", "static Int gC = 3\n"},
	}
	var first string
	for round := 0; round < 20; round++ {
		dir := t.TempDir()
		perm := rand.New(rand.NewSource(int64(round))).Perm(len(files))
		for _, i := range perm { // 创建顺序逐轮变化
			p := filepath.Join(dir, files[i].name)
			if err := os.WriteFile(p, []byte(files[i].src), 0o644); err != nil {
				t.Fatal(err)
			}
		}
		u, diags := LoadUnits(filepath.Join(dir, "main.x"))
		if len(diags) != 0 {
			t.Fatalf("第 %d 轮加载诊断：%v", round, diags)
		}
		var order []string
		for _, d := range u.Decls {
			if f, ok := d.(*xfront.TopField); ok {
				order = append(order, f.Name)
			}
		}
		var out strings.Builder
		code, err := interp.Run(u, &out, nil)
		if err != nil {
			t.Fatalf("第 %d 轮运行失败：%v", round, err)
		}
		got := strings.Join(order, ",") + "|" + out.String() + "|" + strconv.Itoa(code)
		if round == 0 {
			first = got
			if want := "gC,gA,gB,gMain|4123\n|0"; got != want {
				t.Fatalf("初始化序不符合 import 拓扑序（§4.3）：%q，期望 %q", got, want)
			}
			continue
		}
		if got != first {
			t.Fatalf("第 %d 轮（不同文件创建顺序）结果与首轮不一致（DET-01 违约）：%q ≠ %q", round, got, first)
		}
	}
}

// TestDET01EmitCDeterministic —— DET-01 验收要点第 2 项在代码生成侧的延伸：
// 同一编译单元两次生成的 C 源必须逐字节一致（运行结果的编译路径前提）。
func TestDET01EmitCDeterministic(t *testing.T) {
	src := `
class Box {
    Int id = 0

    Int total(Int[] xs) {
        Int sum = self.id
        for k in xs {
            sum = sum + k
        }
        return sum
    }
}

static Int main() {
    Box b = new Box()
    b.id = 2
    Int[] xs = [1, 3]
    print(str(b.total(xs)))
    return 0
}
`
	u, diags := xfront.ParseUnit("det01.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	first, err := EmitC(u)
	if err != nil {
		t.Fatalf("首次代码生成失败：%v", err)
	}
	for round := 1; round <= 5; round++ {
		got, err := EmitC(u)
		if err != nil {
			t.Fatalf("第 %d 轮代码生成失败：%v", round, err)
		}
		if got != first {
			t.Fatalf("第 %d 轮 C 产物与首轮不一致（DET-01 违约）", round)
		}
	}
}
