package codegen

import (
	"os"
	"path/filepath"
	"testing"
)

// writeEmptyResourceTable 为手工 cc 的测试闭合 xrt_resource_* 符号（S6-04）。
func writeEmptyResourceTable(t *testing.T, dir string) string {
	t.Helper()
	p := filepath.Join(dir, "res-empty.c")
	if err := os.WriteFile(p, []byte(emptyResourceTableC), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}
