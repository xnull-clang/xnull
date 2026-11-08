package frontbridge

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// TestNativeDifferentialGate 是 B2-04d 门禁的 Go 入口。
// 默认跳过；设置 XNULL_B2_NATIVE_DIFF=1 并提供原生 xlex/xparser 后执行
// tests/b2/native-diff.sh，任何一层差异都会让本测试失败。
func TestNativeDifferentialGate(t *testing.T) {
	if os.Getenv("XNULL_B2_NATIVE_DIFF") != "1" {
		t.Skip("设置 XNULL_B2_NATIVE_DIFF=1 启用原生差分门禁")
	}
	if os.Getenv("XNULL_NATIVE_XLEX") == "" || os.Getenv("XNULL_NATIVE_XPARSER") == "" {
		t.Skip("需要 XNULL_NATIVE_XLEX / XNULL_NATIVE_XPARSER")
	}
	root := repoRoot(t)
	script := filepath.Join(root, "tests", "b2", "native-diff.sh")
	cmd := exec.Command("bash", script)
	cmd.Dir = root
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("原生差分非零（默认 go 不变）：\n%s", string(out))
	}
	t.Logf("%s", string(out))
}
