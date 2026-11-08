package cli

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/manifest"
)

// S8-13：library 构建 → .xlib → 安装本地仓库 → app 依赖构建成功。
func TestLibraryBuildInstallAndConsume(t *testing.T) {
	root := t.TempDir()
	repo := t.TempDir()
	t.Setenv("XNULL_REPO", repo)

	// 1) library 工程
	libDir := filepath.Join(root, "lib")
	writeFileAt(t, root, "lib/xnull.project", `project {
  groupId = g
  artifactId = lib
  version = 1.0.0
  packaging = library
}
`)
	writeFileAt(t, root, "lib/src/main/x/lib.x", "static Int twice(Int v) {\n    return v * 2\n}\n")
	writeFileAt(t, root, "lib/src/main/resources/templates/t.txt", "lib resource\n")

	var out, errb bytes.Buffer
	env := Env{Stdout: &out, Stderr: &errb}
	if _, code := buildManifest(env, nil, libDir); code != 0 {
		t.Fatalf("library 构建失败，exit=%d\n%s", code, errb.String())
	}
	xlib := filepath.Join(libDir, "target", "lib-1.0.0.xlib")
	data, err := os.ReadFile(xlib)
	if err != nil {
		t.Fatalf("缺少 .xlib：%v", err)
	}
	// 安装到本地仓库
	installed := filepath.Join(repo, "g", "lib", "1.0.0", "lib-1.0.0.xlib")
	if _, err := os.Stat(installed); err != nil {
		t.Fatalf("本地仓库缺少 .xlib：%v", err)
	}
	if _, err := os.Stat(filepath.Join(repo, "g", "lib", "1.0.0", "xnull.project")); err != nil {
		t.Fatalf("本地仓库缺少清单：%v", err)
	}

	// 2) app 工程依赖它
	sum := sha256.Sum256(data)
	lock := &manifest.Lock{Version: 1, Entries: []manifest.LockEntry{{
		Coordinate: "g:lib", Version: "1.0.0", Kind: "dependency",
		Repository: "central", SHA256: hex.EncodeToString(sum[:]),
	}}}
	writeFileAt(t, root, "app/xnull.project", `project {
  groupId = g
  artifactId = app
  version = 1.0.0
  packaging = app
  dependencies {
    dependency g:lib {
      version = 1.0.0
    }
  }
}
`)
	writeFileAt(t, root, "app/src/main/x/main.x", "static Int main() {\n    return 0\n}\n")
	if err := manifest.WriteLock(filepath.Join(root, "app", "xnull.lock"), lock); err != nil {
		t.Fatal(err)
	}
	errb.Reset()
	if _, code := buildManifest(env, nil, filepath.Join(root, "app")); code != 0 {
		t.Fatalf("app 依赖构建失败，exit=%d\n%s", code, errb.String())
	}

	// 3) 负向：锁摘要被篡改 → XPD-406
	lock.Entries[0].SHA256 = strings.Repeat("a", 64)
	if err := manifest.WriteLock(filepath.Join(root, "app", "xnull.lock"), lock); err != nil {
		t.Fatal(err)
	}
	errb.Reset()
	if _, code := buildManifest(env, nil, filepath.Join(root, "app")); code == 0 {
		t.Fatalf("锁摘要不符应构建失败")
	}
	if !strings.Contains(errb.String(), "XPD-406") {
		t.Fatalf("应为 XPD-406：%s", errb.String())
	}
}
