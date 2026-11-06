package codegen

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// TestXdkSeedUnitCompiles 验证 XDK 源码层种子单元（impl/lib/xdk/text.x）
// 在当前语言面上可解析、可通过语义检查并生成 C（M4.6a）。
// 该单元是自举素材的第一步：只用已落地的语言面，不引入 extern/类/枚举。
func TestXdkSeedUnitCompiles(t *testing.T) {
	path, err := filepath.Abs(filepath.Join("..", "..", "lib", "xdk", "text.x"))
	if err != nil {
		t.Fatalf("路径解析失败：%v", err)
	}
	src, err := os.ReadFile(path)
	if err != nil {
		t.Skipf("种子单元不存在（%s），跳过", path)
	}
	u, pdiags := xfront.ParseUnit(path, string(src))
	if len(pdiags) > 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}
	if sd := sema.Analyze(path, u); len(sd) > 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	c, err := EmitC(u)
	if err != nil {
		t.Fatalf("代码生成失败：%v", err)
	}
	for _, sym := range []string{"xn_repeatText", "xn_repeatJoined"} {
		if !strings.Contains(c, sym) {
			t.Fatalf("生成代码缺少 %s", sym)
		}
	}
}
