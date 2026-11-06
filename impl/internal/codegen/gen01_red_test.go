// gen01_red_test.go —— M1 / GEN-01 的「先红」测试（S1 §8，泛型函数）。
//
// 状态：RED（2026-11-07）。只记录缺口，不修改任何现有测试期望、不删测试。
//
// 判定口径（RED 的判据，也是将来变 GREEN 的判据）：
//   - accept 用例：sema 零诊断 + EmitC 成功 + 编译 stdout/退出码 == 解释 stdout/退出码。
//   - reject 用例：必须被拒绝，且**不得**落在「实参 N 类型 X 不能赋给形参 T」
//     这种"类型参数根本没被解析"的形态上——那证明泛型未实现，不证明程序非法。
package codegen

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// gen01WrongReason 判断诊断是否是"泛型未实现"的伪装（而非该条款要求的诊断）。
func gen01WrongReason(ds []string) bool {
	for _, d := range ds {
		if strings.Contains(d, "不能赋给形参 T") || strings.Contains(d, "不能赋给形参 U") ||
			strings.Contains(d, "不能赋给声明的返回类型 T") || strings.Contains(d, "不能赋给声明的返回类型 U") {
			return true
		}
	}
	return false
}

func gen01Accept(t *testing.T, src string) {
	t.Helper()
	u, pdiags := xfront.ParseUnit("g.x", src)
	if len(pdiags) != 0 {
		t.Fatalf("解析诊断（GEN-01 用例不应卡在解析层）：%v", pdiags)
	}
	if sd := sema.Analyze("g.x", u); len(sd) != 0 {
		t.Fatalf("语义诊断（泛型未被解析）：%v", sd)
	}
	if _, err := EmitC(u); err != nil {
		t.Fatalf("代码生成失败：%v", err)
	}
	got, gotCode := compileAndRun(t, src)
	want, wantCode := interpRun(t, src)
	if got != want || gotCode != wantCode {
		t.Fatalf("双路径不一致：\n--- 编译 ---\n%s(code %d)\n--- 解释 ---\n%s(code %d)",
			got, gotCode, want, wantCode)
	}
	t.Logf("OK 输出=%q code=%d", got, gotCode)
}

func gen01Reject(t *testing.T, src string, mustContain ...string) {
	t.Helper()
	u, pdiags := xfront.ParseUnit("g.x", src)
	var all []string
	for _, d := range pdiags {
		all = append(all, d.Code+" "+d.Message)
	}
	if len(pdiags) == 0 {
		if sd := sema.Analyze("g.x", u); len(sd) != 0 {
			for _, d := range sd {
				all = append(all, d.Code+" "+d.Message)
			}
		} else if _, err := EmitC(u); err == nil {
			t.Fatalf("期望编译错误，实际通过（静默接受）")
		} else {
			t.Fatalf("被拒绝，但落在 codegen 内部错误而非诊断：%v", err)
		}
	}
	if len(all) == 0 {
		t.Fatalf("期望诊断，实际无诊断")
	}
	if gen01WrongReason(all) {
		t.Fatalf("被拒绝，但理由是「类型参数未解析」而非条款要求：%v", all)
	}
	joined := strings.Join(all, " ")
	for _, need := range mustContain {
		if !strings.Contains(joined, need) {
			t.Fatalf("诊断未提到 %q：%v", need, all)
		}
	}
}

// TestGEN01 逐项覆盖台账 GEN-01 验收要点（8 项）与 S1 §8 的其余可判定条款。
func TestGEN01(t *testing.T) {
	cases := []struct {
		id     string
		clause string
		src    string
		must   []string
		accept bool
		skip   string
	}{
		// ---- 台账 8 项 ----
		{"G1a", "§8.2 显式类型实参", `
static T identity<T>(T value) { return value }
static Int main() { print(identity<Int>(7)); return 0 }`, nil, true, ""},
		{"G1b", "§8.2 显式类型实参数量必须一致", `
static T identity<T>(T value) { return value }
static Int main() { print(identity<Int, Int>(7)); return 0 }`, []string{"类型实参"}, false, ""},
		{"G2a", "§8.2 推断：类型参数直接匹配实参类型", `
static T identity<T>(T value) { return value }
static Int main() { print(identity(7)); return 0 }`, nil, true, ""},
		{"G2b", "§8.2 推断：嵌套类型逐层匹配", `
static T head<T>(List<T> xs) { return xs.get(0) }
static Int main() {
    List<Int> xs = [4, 5]
    print(head(xs))
    return 0
}`, nil, true, ""},
		{"G2c", "§8.2 无后缀整数字面量绑定 Int", `
static T pick<T>(T a, T b) { return b }
static Int main() { print(pick(1, 2)); return 0 }`, nil, true, ""},
		{"G2d", "§8.2 返回类型上下文不参与推断", `
static T make<T>() { T z = 0; return z }
static Int main() { Int x = make(); print(x); return 0 }`, []string{"类型参数"}, false, ""},
		{"G3", "§8.2 同一类型参数冲突绑定", `
static T pick<T>(T a, T b) { return a }
static Int main() { print(pick(1, "s")); return 0 }`, []string{"冲突"}, false, ""},
		{"G4", "§8.2 结束时仍有未绑定类型参数", `
static T firstOf<T, U>(T a, U b) { return a }
static Int main() { print(firstOf(1, 2)); return 0 }`, []string{"未绑定"}, false, ""},
		{"G5a", "§8.2 重载：唯一候选被选中", `
static Int pick(Int v) { return v + 1 }
static T pick<T>(T v) { return v }
static Int main() { print(pick(3)); return 0 }`, nil, true, ""},
		{"G5b", "§8.2 重载：多个候选适用报歧义", `
static T pick<T>(T a) { return a }
static T pick2<T>(T a) { return a }
static Int main() { print(pick(1)); return 0 }`, []string{"歧义"}, false, ""},
		{"G5c", "§8.2 重载：零候选是编译错误", `
static T pick<T>(T a) { return a }
static Int main() { print(pick(true, false)); return 0 }`, []string{"实参"}, false, ""},
		{"G6a", "§8.3 单态化：两个不同类型实参各自实例", `
static T identity<T>(T value) { return value }
static Int main() {
    print(identity<Int>(1))
    print(identity<String>("s"))
    return 0
}`, nil, true, ""},
		{"G6b", "§8.3 单态化：实例按具体类型检查（T 上的容器操作）", `
static Int count<T>(List<T> xs) { return xs.length() }
static Int main() {
    List<Int> a = [1, 2, 3]
    List<String> b = ["x"]
    print(count(a))
    print(count(b))
    return 0
}`, nil, true, ""},
		{"G7", "§8.3 递归单态化必须终止，超限必须有诊断", `
static T loop<T>(T v) { return loop<T>(v) }
static Int main() { print(loop<Int>(1)); return 0 }`, []string{"展开"}, false,
			"源码级无限展开需嵌套实参 grow<List<T>>(v)：① xfront `>>` 词法阻断（B1b）；② codegen 不支持 List<List<Int>>（嵌套容器未落地）。上限代码 maxInstDepth=64 保留为防御，当前无可执行验收用例"},
		{"G8", "台账：Result 类型实参可实例化", `
static T unwrapOr<T>(Result<T, String> r, T d) { return r.unwrapOr(d) }
static Int main() {
    Result<Int, String> r = Ok(5)
    print(unwrapOr(r, 0))
    return 0
}`, nil, true, ""},

		// ---- S1 §8 其余可判定条款 ----
		{"G9", "§8.1 类型参数只在当前函数可见", `
static T leak<T>(T v) { return v }
static T useTop() { T z = 0; return z }
static Int main() { return 0 }`, []string{"未定义"}, false, ""},
		{"G10", "§8.1 类型参数不得重名", `
static T dup<T, T>(T v) { return v }
static Int main() { print(dup<Int>(1)); return 0 }`, []string{"类型参数"}, false, ""},
		{"G11", "§8.1 类型参数可用于局部变量与嵌套类型", `
static T keep<T>(T v) {
    T local = v
    List<T> box = [v]
    return local
}
static Int main() { print(keep(9)); return 0 }`, nil, true, ""},
		{"G12", "§8.1 泛型函数不能作为值直接使用", `
static T identity<T>(T v) { return v }
static Int main() { print(identity(1)); return 0 }`, nil, true,
			"当前语言面无函数值语法（闭包/函数类型未落地），该条款不可表达；见回执未测项"},
		{"G13", "§8.3 类型参数不能是 void", `
static T nothing<T>() { T z = 0; return z }
static Int main() { nothing<void>(); return 0 }`, []string{"void"}, false, ""},
		{"G14", "§8.3 泛型内 is T / as T 按具体类型检查", `
static Bool isInt<T>(T v) { return v is Int }
static Int main() { print(isInt<Int>(1)); return 0 }`, nil, true, ""},
		{"G15", "§8.3 泛型内不能写 new T()", `
class Box { Int n = 0; }
static T build<T>() { T z = new T(); return z }
static Int main() { build<Box>(); return 0 }`, []string{"new"}, false, ""},
		{"G17", "§8.4 类型约束必须拒绝", `
static T id<T: Comparable>(T v) { return v }
static Int main() { print(id(1)); return 0 }`, nil, false, ""},
		{"G18", "§8.2 泛型与普通函数同名共存", `
static Int plain(Int v) { return v }
static T gen<T>(T v) { return v }
static Int main() { print(plain(2)); print(gen(3)); return 0 }`, nil, true, ""},
		{"G19", "§8.2 null 实参不能让类型参数唯一确定", `
static T id<T>(T v) { return v }
static Int main() { print(id(null)); return 0 }`, []string{"null"}, false, ""},
	}

	for _, c := range cases {
		c := c
		t.Run(c.id+"_"+c.clause, func(t *testing.T) {
			if c.skip != "" {
				t.Skip(c.skip)
			}
			if c.accept {
				gen01Accept(t, c.src)
				return
			}
			gen01Reject(t, c.src, c.must...)
		})
	}
}

// TestGEN01CrossFile §8.3「泛型函数体必须在实例化点可见」：跨文件实例化。
func TestGEN01CrossFile(t *testing.T) {
	dir := writeTree(t, map[string]string{
		"main.x":    "import generic\nstatic Int main() {\n    print(identity(3))\n    return 0\n}",
		"generic.x": "static T identity<T>(T v) { return v }\n",
	})
	entry := filepath.Join(dir, "main.x")
	u, diags := LoadUnits(entry)
	if len(diags) != 0 {
		t.Fatalf("加载诊断：%v", diags)
	}
	if sd := sema.Analyze(entry, u); len(sd) != 0 {
		t.Fatalf("跨文件泛型的语义诊断（模板不可见）：%v", sd)
	}
	if _, err := EmitC(u); err != nil {
		t.Fatalf("跨文件泛型代码生成失败：%v", err)
	}
	// 用例自证：确认写出的文件存在（writeTree 返回目录）
	if _, err := os.Stat(filepath.Join(dir, "generic.x")); err != nil {
		t.Fatal(err)
	}
}
