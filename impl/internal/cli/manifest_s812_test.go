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

// S8-12：parent 继承（build.sourceRoot 从 pom 父工程继承）。
func TestBuildInheritsParentBuild(t *testing.T) {
	root := t.TempDir()
	writeFileAt(t, root, "parent/xnull.project", `project {
  groupId = g
  artifactId = parent
  version = 1.0.0
  packaging = pom
  properties {
    app.name = inherited
  }
  build {
    sourceRoot = alt/src
    warnings = strict
  }
}
`)
	writeFileAt(t, root, "app/xnull.project", `project {
  groupId = g
  artifactId = app
  version = 1.0.0
  packaging = app
  parent {
    groupId = g
    artifactId = parent
    version = 1.0.0
    relativePath = ../parent/xnull.project
  }
}
`)
	writeFileAt(t, root, "app/alt/src/main.x", "static Int main() {\n    return 0\n}\n")

	var out, errb bytes.Buffer
	env := Env{Stdout: &out, Stderr: &errb}
	if _, code := buildManifest(env, nil, filepath.Join(root, "app")); code != 0 {
		t.Fatalf("继承工程应构建通过，exit=%d\n%s", code, errb.String())
	}
	if _, err := os.Stat(filepath.Join(root, "app", "target", "app-1.0.0")); err != nil {
		t.Fatalf("产物缺失：%v", err)
	}
}

// S8-12：依赖工程 + 锁端到端（graph + lock 校验）。
func TestBuildDependencyWithLock(t *testing.T) {
	root := t.TempDir()
	repo := t.TempDir()
	t.Setenv("XNULL_REPO", repo)
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
	writeFileAt(t, repo, "g/lib/1.0.0/xnull.project", `project {
  groupId = g
  artifactId = lib
  version = 1.0.0
  packaging = library
}
`)
	jar := []byte("lib-jar-bytes")
	writeFileAt(t, repo, "g/lib/1.0.0/lib-1.0.0.jar", string(jar))
	sum := sha256.Sum256(jar)
	lock := &manifest.Lock{Version: 1, Entries: []manifest.LockEntry{{
		Coordinate: "g:lib", Version: "1.0.0", Kind: "dependency",
		Repository: "central", SHA256: hex.EncodeToString(sum[:]),
	}}}
	lockPath := filepath.Join(root, "app", "xnull.lock")
	if err := manifest.WriteLock(lockPath, lock); err != nil {
		t.Fatal(err)
	}
	lockBytes, _ := os.ReadFile(lockPath)

	var out, errb bytes.Buffer
	env := Env{Stdout: &out, Stderr: &errb}
	if _, code := buildManifest(env, nil, filepath.Join(root, "app")); code != 0 {
		t.Fatalf("依赖工程应构建通过，exit=%d\n%s", code, errb.String())
	}
	meta, err := os.ReadFile(filepath.Join(root, "app", "target", "app-1.0.0.xmeta"))
	if err != nil {
		t.Fatal(err)
	}
	wantLock := sha256.Sum256(lockBytes)
	if !strings.Contains(string(meta), "lockSha256       = "+hex.EncodeToString(wantLock[:])) {
		t.Fatalf(".xmeta 锁摘要不符：\n%s", meta)
	}

	// 负向：锁版本与清单不一致 → XPD-404。
	lock.Entries[0].Version = "9.9.9"
	if err := manifest.WriteLock(lockPath, lock); err != nil {
		t.Fatal(err)
	}
	errb.Reset()
	if _, code := buildManifest(env, nil, filepath.Join(root, "app")); code == 0 {
		t.Fatalf("锁不一致应构建失败")
	}
	if !strings.Contains(errb.String(), "XPD-404") {
		t.Fatalf("应为 XPD-404：%s", errb.String())
	}
}
