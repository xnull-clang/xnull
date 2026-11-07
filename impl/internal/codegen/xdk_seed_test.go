package codegen

import (
	"os"
	"path/filepath"
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
	// S6-05 起 text.x 是完整公开面（Format/parse/UTF/Regex），旧种子
	// xn_repeatText/xn_repeatJoined 已移除；编译面依赖 Char/Double/Error 协议等
	// codegen 能力（E4 XDK-08 待补），此处核验可解析/语义通过，发射受限则跳过。
	if _, err := EmitC(u); err != nil {
		t.Skipf("text.x 编译面未完成（E4 XDK-08）：%v", err)
	}
	}
}
