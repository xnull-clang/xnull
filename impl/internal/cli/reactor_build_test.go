package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// S8-14：pom 聚合根 → 模块拓扑构建（library 先于 app），产物与聚合摘要齐全。
func TestReactorAggregateBuild(t *testing.T) {
	root := t.TempDir()
	repo := t.TempDir()
	t.Setenv("XNULL_REPO", repo)
	writeFileAt(t, root, "xnull.project", `project {
  groupId = io.xnull
  artifactId = suite
  version = 3.1.0
  packaging = pom
  modules {
    module core
    module app
  }
  dependencyManagement {
    dependencies {
      dependency io.xnull:core {
        version = 3.1.0
      }
    }
  }
}
`)
	writeFileAt(t, root, "core/xnull.project", `project {
  groupId = io.xnull
  artifactId = core
  version = 3.1.0
  packaging = library
}
`)
	writeFileAt(t, root, "core/src/main/x/core.x", "static Int c() {\n    return 1\n}\n")
	writeFileAt(t, root, "app/xnull.project", `project {
  groupId = io.xnull
  artifactId = app
  version = 3.1.0
  packaging = app
  dependencies {
    dependency io.xnull:core {
    }
  }
}
`)
	writeFileAt(t, root, "app/src/main/x/main.x", "static Int main() {\n    return 0\n}\n")

	var out, errb bytes.Buffer
	env := Env{Stdout: &out, Stderr: &errb}
	summary, code := buildManifest(env, nil, root)
	if code != 0 {
		t.Fatalf("聚合构建失败，exit=%d\n%s", code, errb.String())
	}
	if _, err := os.Stat(filepath.Join(root, "core", "target", "core-3.1.0.xlib")); err != nil {
		t.Fatalf("core .xlib 缺失：%v", err)
	}
	appBin := filepath.Join(root, "app", "target", "app-3.1.0")
	if _, err := os.Stat(appBin); err != nil {
		t.Fatalf("app 产物缺失：%v", err)
	}
	data, err := os.ReadFile(summary)
	if err != nil {
		t.Fatalf("聚合摘要缺失：%v", err)
	}
	coreIdx := strings.Index(string(data), "module core ")
	appIdx := strings.Index(string(data), "module app ")
	if coreIdx < 0 || appIdx < 0 || coreIdx > appIdx {
		t.Fatalf("聚合摘要顺序不符（library 应先于 app）：\n%s", data)
	}
	// 模块构建后 core 已安装到本地仓库
	if _, err := os.Stat(filepath.Join(repo, "io", "xnull", "core", "3.1.0", "core-3.1.0.xlib")); err != nil {
		t.Fatalf("core 未安装到本地仓库：%v", err)
	}

	// 负向：app 源码语法错误 → 失败即停；core 已构建，app 不产物。
	writeFileAt(t, root, "app/src/main/x/main.x", "static Int main( {\n")
	errb.Reset()
	if _, code := buildManifest(env, nil, root); code == 0 {
		t.Fatalf("语法错误应构建失败")
	}
	if !strings.Contains(errb.String(), "XPD-201") && !strings.Contains(errb.String(), "模块 app 构建失败") {
		t.Fatalf("应点名模块失败：%s", errb.String())
	}
}
