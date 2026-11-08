package codegen

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xdkcheck"
	"xnull.dev/xnull/internal/xfront"
)

// S6-09：xdk.net 源码单元——socket plain/Async + xdk.net.http 子包入口。
// 合同来源：S6 §4.7 / ADR-009 / E2 S6-09 签名（connect/bind/Socket/Listener/Request/Response）。
func TestS609NetUnitSurface(t *testing.T) {
	path, err := filepath.Abs(filepath.Join("..", "..", "lib", "xdk", "net.x"))
	if err != nil {
		t.Fatal(err)
	}
	src, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("读取 net.x 失败：%v", err)
	}
	text := string(src)
	u, pdiags := xfront.ParseUnit(path, text)
	if len(pdiags) > 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}

	classes := map[string]*xfront.ClassDecl{}
	funcs := map[string]*xfront.TopFunc{}
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.ClassDecl:
			classes[n.Name] = n
		case *xfront.TopFunc:
			funcs[n.Name] = n
		}
	}

	for _, name := range []string{"Socket", "Listener", "Request", "Response"} {
		if classes[name] == nil {
			t.Errorf("缺少类型 %s", name)
		}
	}
	for _, name := range []string{
		"connect", "connectAsync", "bind", "bindAsync",
		"get", "post", "getAsync", "postAsync",
	} {
		if funcs[name] == nil {
			t.Errorf("缺少入口函数 %s", name)
		}
	}

	wantMethods := map[string][]string{
		"Socket":   []string{"connect", "connectAsync", "read", "readAsync", "write", "writeAsync", "close"},
		"Listener": []string{"bind", "bindAsync", "accept", "acceptAsync", "close"},
		"Response": []string{"status", "body", "header"},
	}
	for cls, names := range wantMethods {
		c := classes[cls]
		if c == nil {
			continue
		}
		got := map[string]bool{}
		for _, m := range c.Methods {
			got[m.Name] = true
		}
		for _, name := range names {
			if !got[name] {
				t.Errorf("%s 缺少方法 %s", cls, name)
			}
		}
	}

	// 双形态：*Async 必须是首参 Context；plain 不写 Context。
	for name, fn := range funcs {
		isAsync := strings.HasSuffix(name, "Async")
		hasCtx := len(fn.Params) > 0 && xfront.PrintType(fn.Params[0].Type) == "Context"
		if isAsync && !hasCtx {
			t.Errorf("%s 缺少首参 Context（S6 §4.7 定案 3-g-2）", name)
		}
		if !isAsync && hasCtx {
			t.Errorf("%s 是 plain 形态，不应带 Context", name)
		}
	}
	for cls, names := range map[string][]string{"Socket": []string{"connectAsync", "readAsync", "writeAsync"}, "Listener": []string{"bindAsync", "acceptAsync"}} {
		c := classes[cls]
		if c == nil {
			continue
		}
		for _, m := range c.Methods {
			for _, want := range names {
				if m.Name != want {
					continue
				}
				if len(m.Params) == 0 || xfront.PrintType(m.Params[0].Type) != "Context" {
					t.Errorf("%s.%s 缺少首参 Context", cls, m.Name)
				}
			}
		}
	}

	// 可失败入口返回 Result；资源 close 返回 Result<void, Error>。
	for name, fn := range funcs {
		if name == "netErr" || name == "isValidAddress" || name == "isHttpUrl" {
			continue
		}
		got := xfront.PrintType(fn.Ret)
		if !strings.HasPrefix(got, "Result<") || !strings.Contains(got, "Error") {
			t.Errorf("%s 返回 %q，必须为 Result<_, Error>", name, got)
		}
	}
	for _, cls := range []string{"Socket", "Listener"} {
		c := classes[cls]
		if c == nil {
			continue
		}
		for _, m := range c.Methods {
			if m.Name != "close" {
				continue
			}
			if got := xfront.PrintType(m.Ret); got != "Result<void, Error>" {
				t.Errorf("%s.close 返回 %q，必须为 Result<void, Error>", cls, got)
			}
		}
	}

	// S6-08 包骨架：首行包名 + 单一稳定性标记。
	first := ""
	for _, line := range strings.Split(text, "\n") {
		if strings.TrimSpace(line) != "" {
			first = line
			break
		}
	}
	if !strings.Contains(first, "xdk.net") {
		t.Errorf("首行缺少 xdk.net 包名标注：%q", first)
	}
	if strings.Count(text, "@preview") != 1 {
		t.Errorf("net.x 必须且只能有一个 @preview 稳定性标记")
	}

	// 语义检查：单元自身在当前 xfront/sema 面上零诊断。
	if sd := sema.Analyze(path, u); len(sd) > 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
}

// S6-09：net.x 必须通过 XDK 静态合同（依赖矩阵/命名/稳定性/无全局可变）。
func TestS609NetContracts(t *testing.T) {
	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "impl", "lib", "xdk", "net.x")); err != nil {
		t.Skip("XDK 单元未合入当前分支")
	}
	vs := xdkcheck.CheckContracts(root)
	for _, v := range vs {
		if strings.Contains(v.File, "net.x") || strings.Contains(v.Message, "net") {
			t.Errorf("XDK 合同违约：%s", v)
		}
	}
}

// S6-09：`import xdk.net` 与 `import xdk.net.http` 都能经 S6-08 loader 装载。
func TestS609NetLoader(t *testing.T) {
	if _, err := os.Stat(filepath.Join("..", "..", "lib", "xdk", "net.x")); err != nil {
		t.Skip("XDK 单元未合入当前分支")
	}
	dir := t.TempDir()
	mainPath := filepath.Join(dir, "main.x")
	src := "import xdk.net\nimport xdk.net.http\n\nstatic Int main() {\n    return 0\n}\n"
	if err := os.WriteFile(mainPath, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	u, diags := LoadUnits(mainPath)
	if len(diags) > 0 {
		t.Fatalf("装载诊断：%v", diags)
	}
	found := map[string]bool{}
	for _, d := range u.Decls {
		if c, ok := d.(*xfront.ClassDecl); ok {
			found[c.Name] = true
		}
	}
	for _, name := range []string{"Socket", "Listener", "Response"} {
		if !found[name] {
			t.Errorf("loader 未装载 %s 声明", name)
		}
	}
}
