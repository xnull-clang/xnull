package cli

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// S8-03：xnull lock 生成/校验/--update-lock 三态。
func TestLockCommand(t *testing.T) {
	dir := t.TempDir()
	proj := `project {
  groupId    = g
  artifactId = app
  version    = 1.0.0
  packaging  = app
  dependencyManagement {
    dependencies {
      dependency g:lib {
        version = 2.0.0
      }
    }
  }
  dependencies {
    dependency g:lib {
    }
  }
}
`
	if err := os.WriteFile(filepath.Join(dir, "xnull.project"), []byte(proj), 0o644); err != nil {
		t.Fatal(err)
	}
	repo := t.TempDir()
	art := filepath.Join(repo, "g", "lib", "2.0.0", "lib-2.0.0.jar")
	if err := os.MkdirAll(filepath.Dir(art), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(art, []byte("bytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XNULL_REPO", repo)

	// 无锁 → 校验失败
	if code, _, _ := run("lock", dir); code == 0 {
		t.Fatalf("缺锁应失败")
	}
	// --update-lock 生成
	if code, _, errOut := run("lock", "--update-lock", dir); code != 0 {
		t.Fatalf("生成锁失败：%s", errOut)
	}
	lock, err := os.ReadFile(filepath.Join(dir, "xnull.lock"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(lock), "entry g:lib 2.0.0") {
		t.Fatalf("锁内容不符：\n%s", lock)
	}
	sum := sha256.Sum256([]byte("bytes"))
	if !strings.Contains(string(lock), hex.EncodeToString(sum[:])) {
		t.Fatalf("摘要不符：\n%s", lock)
	}
	// 校验通过
	if code, _, errOut := run("lock", dir); code != 0 {
		t.Fatalf("锁校验失败：%s", errOut)
	}
	// 清单变更 → 锁不一致
	if err := os.WriteFile(filepath.Join(dir, "xnull.project"), []byte(strings.Replace(proj, "2.0.0", "3.0.0", 1)), 0o644); err != nil {
		t.Fatal(err)
	}
	os.Remove(filepath.Join(repo, "g", "lib", "2.0.0", "lib-2.0.0.jar"))
	art3 := filepath.Join(repo, "g", "lib", "3.0.0", "lib-3.0.0.jar")
	os.MkdirAll(filepath.Dir(art3), 0o755)
	os.WriteFile(art3, []byte("bytes3"), 0o644)
	code, _, errOut := run("lock", dir)
	if code != 1 {
		t.Fatalf("清单变更后应报锁不一致，实际 %d", code)
	}
	if !strings.Contains(errOut, "XPD-404") {
		t.Fatalf("应为 XPD-404：%s", errOut)
	}
}
