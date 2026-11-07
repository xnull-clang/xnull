package manifest

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/diag"
)

const depsParent = `project {
  groupId    = g
  artifactId = parent
  version    = 1.0.0
  packaging  = pom
  dependencyManagement {
    dependencies {
      dependency g:lib {
        version = 2.0.0
      }
    }
  }
}
`

func depsChild(extra string) string {
	return `project {
  groupId    = g
  artifactId = child
  version    = 1.0.0
  packaging  = app
  parent {
    groupId      = g
    artifactId   = parent
    version      = 1.0.0
    relativePath = ../xnull.project
  }
  dependencies {
    dependency g:lib {
    }
  }
` + extra + `}
`
}

func loadDeps(t *testing.T, body string, opts Options) (*Resolved, []diag.Diagnostic) {
	t.Helper()
	dir := t.TempDir()
	write(t, dir, "xnull.project", depsParent)
	p := write(t, dir, "child/xnull.project", body)
	res, diags, err := ResolveDependencies(p, opts)
	if err != nil {
		t.Fatalf("IO 错误：%v", err)
	}
	return res, diags
}

func hasDiag(ds []diag.Diagnostic, code string) bool {
	for _, d := range ds {
		if strings.HasPrefix(d.Code, code) {
			return true
		}
	}
	return false
}

// S8-03：dependencyManagement 提供版本；缺版本/非法形态失败；显式覆盖告警。
func TestDependencyManagement(t *testing.T) {
	t.Run("管理版本生效", func(t *testing.T) {
		res, diags := loadDeps(t, depsChild(""), Options{})
		if len(diags) != 0 {
			t.Fatalf("不应有诊断：%v", diags)
		}
		if res.Dependencies["g:lib"] != "2.0.0" {
			t.Fatalf("管理版本未生效：%v", res.Dependencies)
		}
	})

	t.Run("缺版本失败", func(t *testing.T) {
		body := `project {
  groupId = g
  artifactId = child
  version = 1.0.0
  packaging = app
  dependencies {
    dependency g:nover {
    }
  }
}
`
		_, diags := loadDeps(t, body, Options{})
		if !hasDiag(diags, "XPD-401") {
			t.Fatalf("缺版本应报 XPD-401：%v", diags)
		}
	})

	t.Run("范围/SNAPSHOT/LATEST 拒绝", func(t *testing.T) {
		for _, bad := range []string{"[1.0,2.0)", "1.0.0-SNAPSHOT", "LATEST", "RELEASE", "*"} {
			body := `project {
  groupId = g
  artifactId = child
  version = 1.0.0
  packaging = app
  dependencies {
    dependency g:lib {
      version = "` + bad + `"
    }
  }
}
`
			_, diags := loadDeps(t, body, Options{})
			if !hasDiag(diags, "XPD-402") {
				t.Fatalf("%q 应报 XPD-402：%v", bad, diags)
			}
		}
	})

	t.Run("预发布精确版本允许", func(t *testing.T) {
		body := `project {
  groupId = g
  artifactId = child
  version = 1.0.0
  packaging = app
  dependencies {
    dependency g:lib {
      version = 1.2.3-rc.1
    }
  }
}
`
		res, diags := loadDeps(t, body, Options{})
		if len(diags) != 0 {
			t.Fatalf("预发布精确版本应允许：%v", diags)
		}
		if res.Dependencies["g:lib"] != "1.2.3-rc.1" {
			t.Fatalf("版本解析错误：%v", res.Dependencies)
		}
	})

	t.Run("显式覆盖管理版本产生告警", func(t *testing.T) {
		res, diags := loadDeps(t, `project {
  groupId = g
  artifactId = child
  version = 1.0.0
  packaging = app
  parent {
    groupId = g
    artifactId = parent
    version = 1.0.0
    relativePath = ../xnull.project
  }
  dependencies {
    dependency g:lib {
      version = 3.0.0
    }
  }
}
`, Options{})
		if len(diags) != 0 {
			t.Fatalf("覆盖不应失败：%v", diags)
		}
		if res.Dependencies["g:lib"] != "3.0.0" {
			t.Fatalf("显式版本未生效：%v", res.Dependencies)
		}
		if len(res.Warnings) == 0 {
			t.Fatalf("应产生覆盖告警")
		}
	})

	t.Run("管理表含 scope 失败", func(t *testing.T) {
		dir := t.TempDir()
		write(t, dir, "xnull.project", `project {
  groupId = g
  artifactId = parent
  version = 1.0.0
  packaging = pom
  dependencyManagement {
    dependencies {
      dependency g:lib {
        version = 2.0.0
        scope = compile
      }
    }
  }
}
`)
		write(t, dir, "child/xnull.project", depsChild(""))
		_, diags, _ := ResolveDependencies(filepath.Join(dir, "child/xnull.project"), Options{})
		if !hasDiag(diags, "XPD-407") {
			t.Fatalf("管理表 scope 应报 XPD-407：%v", diags)
		}
	})
}

// S8-03：xnull.lock 生成、排序、校验。
func TestLockGenerateAndValidate(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "xnull.project", depsParent)
	proj := write(t, dir, "child/xnull.project", depsChild(""))
	// 本地仓库：g/lib/2.0.0/lib-2.0.0.jar
	repo := t.TempDir()
	art := filepath.Join(repo, "g", "lib", "2.0.0", "lib-2.0.0.jar")
	if err := os.MkdirAll(filepath.Dir(art), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(art, []byte("artifact-bytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XNULL_REPO", repo)

	res, diags, err := ResolveDependencies(proj, Options{})
	if err != nil || len(diags) != 0 {
		t.Fatalf("解析失败：%v %v", err, diags)
	}
	lock, diags := GenerateLock(res, repo, nil)
	if len(diags) != 0 {
		t.Fatalf("生成锁失败：%v", diags)
	}
	if len(lock.Entries) != 1 || lock.Entries[0].Coordinate != "g:lib" || lock.Entries[0].Version != "2.0.0" {
		t.Fatalf("锁条目错误：%+v", lock.Entries)
	}
	sum := sha256.Sum256([]byte("artifact-bytes"))
	if lock.Entries[0].SHA256 != hex.EncodeToString(sum[:]) {
		t.Fatalf("摘要错误：%s", lock.Entries[0].SHA256)
	}

	lockPath := filepath.Join(dir, "xnull.lock")
	if err := WriteLock(lockPath, lock); err != nil {
		t.Fatal(err)
	}
	loaded, diags, err := LoadLock(lockPath)
	if err != nil || len(diags) != 0 {
		t.Fatalf("读锁失败：%v %v", err, diags)
	}
	if ds := ValidateLock(loaded, res, repo); len(ds) != 0 {
		t.Fatalf("锁应通过校验：%v", ds)
	}

	t.Run("锁缺条目", func(t *testing.T) {
		empty := &Lock{Version: 1}
		if ds := ValidateLock(empty, res, repo); !hasDiag(ds, "XPD-404") {
			t.Fatalf("缺条目应报 XPD-404：%v", ds)
		}
	})
	t.Run("锁多余坐标", func(t *testing.T) {
		extra := &Lock{Version: 1, Entries: []LockEntry{{Coordinate: "g:extra", Version: "1.0.0", Kind: "dependency",
			Repository: "central", SHA256: strings.Repeat("0", 64)}}}
		if ds := ValidateLock(extra, res, repo); !hasDiag(ds, "XPD-405") {
			t.Fatalf("多余坐标应报 XPD-405：%v", ds)
		}
	})
	t.Run("摘要不符", func(t *testing.T) {
		bad := &Lock{Version: 1, Entries: []LockEntry{{Coordinate: "g:lib", Version: "2.0.0", Kind: "dependency",
			Repository: "central", SHA256: strings.Repeat("a", 64)}}}
		if ds := ValidateLock(bad, res, repo); !hasDiag(ds, "XPD-406") {
			t.Fatalf("摘要不符应报 XPD-406：%v", ds)
		}
	})
	t.Run("锁与清单版本不一致", func(t *testing.T) {
		bad := &Lock{Version: 1, Entries: []LockEntry{{Coordinate: "g:lib", Version: "9.9.9", Kind: "dependency",
			Repository: "central", SHA256: strings.Repeat("0", 64)}}}
		if ds := ValidateLock(bad, res, repo); !hasDiag(ds, "XPD-404") {
			t.Fatalf("版本不一致应报 XPD-404：%v", ds)
		}
	})
}

func TestLockSortOrder(t *testing.T) {
	l := &Lock{Version: 1, Entries: []LockEntry{
		{Coordinate: "g:z", Version: "1.0.0", Kind: "dependency", Repository: "central", SHA256: strings.Repeat("0", 64)},
		{Coordinate: "g:a", Version: "1.0.0", Kind: "dependency", Repository: "central", SHA256: strings.Repeat("0", 64)},
	}}
	p := filepath.Join(t.TempDir(), "xnull.lock")
	if err := WriteLock(p, l); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(p)
	if strings.Index(string(data), "entry g:a") > strings.Index(string(data), "entry g:z") {
		t.Fatalf("锁条目未按坐标升序：\n%s", data)
	}
}
