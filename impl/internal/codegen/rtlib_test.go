// S8-21：codegen 测试链接预编译 libxnrt.a，避免每个用例重编运行时 C 源。
package codegen

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"sync"
	"testing"
)

var (
	rtLibOnce sync.Once
	rtLibPath string
	rtLibErr  error
)

// runtimeLib 返回 libxnrt.a 路径（进程内只构建一次）。
func runtimeLib(t *testing.T) string {
	t.Helper()
	rtLibOnce.Do(func() {
		rt := filepath.Join("..", "..", "..", "impl", "runtime")
		cmd := exec.Command("sh", "build_rt.sh", "--lib")
		cmd.Dir = rt
		if out, err := cmd.CombinedOutput(); err != nil {
			rtLibErr = fmt.Errorf("构建 libxnrt.a 失败：%v\n%s", err, out)
			return
		}
		rtLibPath = filepath.Join(rt, "libxnrt.a")
	})
	if rtLibErr != nil {
		t.Fatalf("%v", rtLibErr)
	}
	return rtLibPath
}
