// gen01_mono_test.go —— GEN-01 的 codegen 半边：单态化实例发射（S1 §8.3）。
//
// 这些用例**绕过 sema**，直接对 `EmitC` 喂已带 `Call.TypeArgs` 的 AST，
// 用来独立验证本域（codegen）的职责：
//   - 每个类型实参列表生成一个独立 C 函数实例；
//   - 实例内 `T` 替换为具体 C 类型（含 List<T> / Result<T,String> 等嵌套）；
//   - 实例名是内部编码，不外露；
//   - 递归单态化超限必须报错，不得静默截断。
//
// 端到端（经 sema + 双路径）的验收在 `gen01_red_test.go`（当前 RED，
// 阻塞在 sema/xfront/interp 三个跨域包，见 evidence/M1-GEN-01/checklist.md）。
package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// emitOnly 只做解析 + EmitC（不过 sema），返回 C 源。
func emitOnly(t *testing.T, src string) string {
	t.Helper()
	u, diags := xfront.ParseUnit("g.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	c, err := EmitC(u)
	if err != nil {
		t.Fatalf("代码生成失败：%v", err)
	}
	return c
}

// runC 把 C 源编译并运行，返回 stdout 与退出码。
func runC(t *testing.T, csrc string) (string, int) {
	t.Helper()
	dir := t.TempDir()
	cfile := filepath.Join(dir, "prog.c")
	if err := os.WriteFile(cfile, []byte(csrc), 0o644); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(dir, "prog")
	cc := exec.Command("cc", "-std=c11", "-I", "../../../impl/runtime", "-O2", "-o", bin,
		cfile, "../../../impl/runtime/rt.c", "../../../impl/runtime/rt_gc.c",
		"../../../impl/runtime/rt_policy.c", "../../../impl/runtime/rt_weak.c")
	var ccerr bytes.Buffer
	cc.Stderr = &ccerr
	if err := cc.Run(); err != nil {
		t.Fatalf("cc 编译失败：%v\n%s\n--- C ---\n%s", err, ccerr.String(), csrc)
	}
	var out bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	code := 0
	if err := run.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		} else {
			t.Fatal(err)
		}
	}
	return out.String(), code
}

func emitAndRun(t *testing.T, src string) (string, int) {
	t.Helper()
	return runC(t, emitOnly(t, src))
}

// TestGEN01MonoExplicit 显式类型实参 → 独立实例（G1a / G6a / G8 的发射半段）。
func TestGEN01MonoExplicit(t *testing.T) {
	src := `
static T identity<T>(T value) {
    return value
}
static Int main() {
    print(identity<Int>(7))
    print(identity<String>("s"))
    return 0
}`
	c := emitOnly(t, src)
	// 实例名是内部编码：同名不同实参必须各成一个 C 函数
	if !strings.Contains(c, "xn_identity_i(") || !strings.Contains(c, "xn_identity_s(") {
		t.Fatalf("未生成两个单态化实例：\n%s", c)
	}
	if strings.Contains(c, "T xn_p_value") || strings.Contains(c, "T value") {
		t.Fatalf("实例内仍残留类型参数 T：\n%s", c)
	}
	got, code := runC(t, c)
	if got != "7\ns\n" || code != 0 {
		t.Fatalf("输出 %q code %d，期望 %q", got, code, "7\ns\n")
	}
}

// TestGEN01MonoNested 嵌套泛型实参 List<T> / Result<T,String> 的替换（G6b / G8）。
func TestGEN01MonoNested(t *testing.T) {
	src := `
static Int count<T>(List<T> xs) {
    return xs.length()
}
static T orElse<T>(Result<T, String> r, T fallback) {
    return r.unwrapOr(fallback)
}
static Int main() {
    List<Int> xs = [1, 2, 3]
    print(count<Int>(xs))
    Result<Int, String> ok = Ok(5)
    Result<Int, String> bad = Err("boom")
    print(orElse<Int>(ok, 0))
    print(orElse<Int>(bad, 9))
    return 0
}`
	c := emitOnly(t, src)
	if !strings.Contains(c, "xn_count_i(") {
		t.Fatalf("List<T> 未替换为具体元素类型（期望实例 xn_count_i）：\n%s", c)
	}
	if !strings.Contains(c, "xn_Result_Int_String") {
		t.Fatalf("Result<T,String> 未替换：\n%s", c)
	}
	got, code := runC(t, c)
	if got != "3\n5\n9\n" || code != 0 {
		t.Fatalf("输出 %q code %d，期望 %q", got, code, "3\n5\n9\n")
	}
}

// TestGEN01MonoOverloadCoexist 泛型与同名普通函数共存（G5a/G18 的发射半段）。
func TestGEN01MonoOverloadCoexist(t *testing.T) {
	src := `
static Int pick(Int v) {
    return v + 1
}
static T pick<T>(T v) {
    return v
}
static Int main() {
    print(pick(3))
    print(pick<Int>(10))
    return 0
}`
	c := emitOnly(t, src)
	if !strings.Contains(c, "static int64_t xn_pick(") {
		t.Fatalf("普通函数未按原名发射：\n%s", c)
	}
	if !strings.Contains(c, "xn_pick_i(") {
		t.Fatalf("泛型实例未按实例名发射：\n%s", c)
	}
	got, code := runC(t, c)
	if got != "4\n10\n" || code != 0 {
		t.Fatalf("输出 %q code %d，期望 %q", got, code, "4\n10\n")
	}
}

// TestGEN01MonoTypeArgEncoding 实例名编码：确定性、可嵌套、拒绝未解析的类型参数。
//
// 说明：「无限展开诊断」(G7) 当前**不可测**：触发无限展开要求类型阶增长（
// grow<List<T>>），但 (a) 源码写法被 xfront 的 `>>` 词法阻断（B1b），
// (b) codegen 的容器元素类型只支持 Int/Bool/String/类引用，`List<List<Int>>`
// 直接报「容器元素类型暂支持…」。上限代码（maxInstDepth）保留为防御，等
// 嵌套容器切片落地后再补端到端用例。
func TestGEN01MonoTypeArgEncoding(t *testing.T) {
	i := &xfront.NamedType{P: xfront.Pos{Line: 1, Col: 1}, Qual: []string{"Int"}}
	s := &xfront.NamedType{P: xfront.Pos{Line: 1, Col: 1}, Qual: []string{"String"}}
	list := func(e xfront.TypeRef) *xfront.NamedType {
		return &xfront.NamedType{P: xfront.Pos{Line: 1, Col: 1}, Qual: []string{"List"}, Args: []xfront.TypeRef{e}}
	}
	res := func(a, b xfront.TypeRef) *xfront.NamedType {
		return &xfront.NamedType{P: xfront.Pos{Line: 1, Col: 1}, Qual: []string{"Result"}, Args: []xfront.TypeRef{a, b}}
	}
	cases := []struct {
		in   xfront.TypeRef
		want string
	}{
		{i, "i"},
		{s, "s"},
		{list(i), "Li"},
		{list(list(s)), "LLs"},
		{res(i, s), "Ri_s"},
	}
	for _, c := range cases {
		got, err := typeArgCode(c.in)
		if err != nil {
			t.Fatalf("编码失败：%v", err)
		}
		if got != c.want {
			t.Fatalf("编码 %q，期望 %q", got, c.want)
		}
	}
	// 未解析的类型参数不能进实例名（否则会生成 xn_f_T 这类未替换符号）
	tp := &xfront.NamedType{P: xfront.Pos{Line: 1, Col: 1}, Qual: []string{"T"}}
	fn := &xfront.TopFunc{Name: "f", TypePars: []string{"T"},
		Ret: &xfront.NamedType{P: xfront.Pos{Line: 1, Col: 1}, Qual: []string{"T"}}}
	g := &gen{generics: map[string]*xfront.TopFunc{"f": fn},
		insts: map[string]*instInfo{}, fnRet: map[string]string{}, cs: newContainers(),
		classes: map[string]*classInfo{}}
	if _, err := g.needInstance("f", []xfront.TypeRef{tp}); err == nil {
		t.Fatal("未解析的类型参数 T 应被拒绝")
	}
	// void 不能作类型实参（§8.3）
	vd := &xfront.NamedType{P: xfront.Pos{Line: 1, Col: 1}, Qual: []string{"void"}}
	if _, err := typeArgCode(vd); err == nil {
		t.Fatal("void 类型实参应被拒绝（§8.3）")
	}
}

// TestGEN01MonoMissingTypeArgs 缺类型实参必须显式报错，不静默降级。
func TestGEN01MonoMissingTypeArgs(t *testing.T) {
	src := `
static T identity<T>(T v) {
    return v
}
static Int main() {
    print(identity(1))
    return 0
}`
	u, diags := xfront.ParseUnit("g.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	_, err := EmitC(u)
	if err == nil {
		t.Fatal("期望「缺少类型实参」错误，实际成功")
	}
	if !strings.Contains(err.Error(), "类型实参") {
		t.Fatalf("诊断内容 %v，期望提到类型实参", err)
	}
}

// TestGEN01MonoWrongTypeArgCount 类型实参数量不符必须报错（G1b 的发射半段兜底）。
func TestGEN01MonoWrongTypeArgCount(t *testing.T) {
	src := `
static T identity<T>(T v) {
    return v
}
static Int main() {
    print(identity<Int, Int>(1))
    return 0
}`
	u, diags := xfront.ParseUnit("g.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	_, err := EmitC(u)
	if err == nil {
		t.Fatal("期望类型实参数量错误，实际成功")
	}
	if !strings.Contains(err.Error(), "类型实参") {
		t.Fatalf("诊断内容 %v，期望提到类型实参", err)
	}
}

// TestGEN01MonoDeterministic 同源两次 EmitC 必须逐字节一致（DET-01）。
func TestGEN01MonoDeterministic(t *testing.T) {
	src := `
static T a<T>(T v) { return v }
static T b<T>(T v) { return v }
static Int main() {
    print(a<String>("x"))
    print(b<Int>(1))
    print(a<Int>(2))
    return 0
}`
	one := emitOnly(t, src)
	two := emitOnly(t, src)
	if one != two {
		t.Fatal("两次 EmitC 产物不一致（DET-01）")
	}
}
