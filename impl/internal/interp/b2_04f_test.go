package interp

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"xnull.dev/xnull/internal/xfront"
)

// B2-04f 回归：xparser.x 解析 `factory F for T { ... }` 时，`{` 位于 target 之后。
// 旧逻辑在解析 target 之前消费 `{`，导致 target 解析完后 `{` 未被消费，
// parseTypeDecl 的成员循环原地打转（解释器上表现为 TestS2BND08CrossPackageStatic 超时）。
// 该用例带超时，防止再次出现“无进展循环”。
func TestXParserFactoryDeclTerminates(t *testing.T) {
	path := filepath.Join("..", "..", "lib", "b2", "xparser.x")
	src, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("读取 xparser.x：%v", err)
	}
	u, diags := xfront.ParseUnit(path, string(src))
	if len(diags) != 0 {
		t.Fatalf("xparser.x 自身解析失败：%v", diags)
	}
	const input = `factory DeviceFactory for Device {
    static Device create(String n) {
        return Device.make(n)
    }
}
`
	type result struct {
		code int
		err  error
		out  string
	}
	done := make(chan result, 1)
	go func() {
		var out bytes.Buffer
		code, runErr := Run(u, &out, []string{input})
		done <- result{code: code, err: runErr, out: out.String()}
	}()
	select {
	case r := <-done:
		if r.err != nil {
			t.Fatalf("解释执行失败：%v", r.err)
		}
		if r.code != 0 {
			t.Fatalf("退出码 %d，期望 0；输出：%s", r.code, r.out)
		}
		if !strings.Contains(r.out, "(FactoryDecl") {
			t.Fatalf("输出缺少 FactoryDecl：%s", r.out)
		}
		if !strings.Contains(r.out, "(Target (NamedType") {
			t.Fatalf("factory Target 未解析：%s", r.out)
		}
	case <-time.After(15 * time.Second):
		t.Fatal("xparser.x 解释执行 15s 未完成：factory 声明的 `{` 未被消费，可能出现无进展循环")
	}
}
