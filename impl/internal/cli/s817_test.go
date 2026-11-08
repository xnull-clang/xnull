package cli

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/exitcode"
)

func depFixture(t *testing.T) (root, repo string) {
	t.Helper()
	root = t.TempDir()
	repo = t.TempDir()
	t.Setenv("XNULL_REPO", repo)
	writeFileAt(t, root, "xnull.project", `project {
  groupId = g
  artifactId = app
  version = 1.0.0
  packaging = app
  dependencies {
    dependency g:a {
      version = 1.0.0
    }
  }
}
`)
	writeFileAt(t, root, "src/main/x/main.x", "static Int main() {\n    return 0\n}\n")
	writeFileAt(t, repo, "g/a/1.0.0/xnull.project", `project {
  groupId = g
  artifactId = a
  version = 1.0.0
  packaging = library
  dependencies {
    dependency g:b {
      version = 2.0.0
    }
  }
}
`)
	writeFileAt(t, repo, "g/a/1.0.0/a-1.0.0.jar", "a")
	writeFileAt(t, repo, "g/b/2.0.0/xnull.project", `project {
  groupId = g
  artifactId = b
  version = 2.0.0
  packaging = library
}
`)
	writeFileAt(t, repo, "g/b/2.0.0/b-2.0.0.jar", "b")
	return root, repo
}

// S8-17：tree 输出依赖树与仲裁版本。
func TestTreeCommand(t *testing.T) {
	root, _ := depFixture(t)
	code, out, errOut := run("tree", root)
	if code != exitcode.Success {
		t.Fatalf("tree 应成功：%s", errOut)
	}
	for _, want := range []string{"g:app@1.0.0", "g:a@1.0.0", "g:b@2.0.0"} {
		if !strings.Contains(out, want) {
			t.Fatalf("tree 缺少 %q：\n%s", want, out)
		}
	}
}

// S8-17：why 解释引入路径；未知坐标报错。
func TestWhyCommand(t *testing.T) {
	root, _ := depFixture(t)
	code, out, errOut := run("why", "g:b", root)
	if code != exitcode.Success {
		t.Fatalf("why 应成功：%s", errOut)
	}
	if !strings.Contains(out, "g:a@1.0.0") || !strings.Contains(out, "g:b@2.0.0") {
		t.Fatalf("why 未给出路径：\n%s", out)
	}
	if code, _, errOut := run("why", "g:nope", root); code == exitcode.Success || !strings.Contains(errOut, "未") {
		t.Fatalf("未知坐标应失败并提示：code=%d %s", code, errOut)
	}
}

// S8-17：install 把产物装入本地仓库。
func TestInstallCommand(t *testing.T) {
	root, repo := depFixture(t)
	// 改为 library 工程以便产生 .xlib
	writeFileAt(t, root, "xnull.project", `project {
  groupId = g
  artifactId = app
  version = 1.0.0
  packaging = library
}
`)
	writeFileAt(t, root, "src/main/x/lib.x", "static Int f() {\n    return 0\n}\n")
	code, out, errOut := run("install", root)
	if code != exitcode.Success {
		t.Fatalf("install 应成功：%s%s", out, errOut)
	}
	installed := filepath.Join(repo, "g", "app", "1.0.0", "app-1.0.0.xlib")
	data, err := os.ReadFile(installed)
	if err != nil {
		t.Fatalf("仓库缺少 .xlib：%v", err)
	}
	sum := sha256.Sum256(data)
	if !strings.Contains(out, hex.EncodeToString(sum[:])) {
		t.Fatalf("install 输出应含 sha256：%s", out)
	}
	if _, err := os.Stat(filepath.Join(repo, "g", "app", "1.0.0", "xnull.project")); err != nil {
		t.Fatalf("仓库缺少清单：%v", err)
	}
}
