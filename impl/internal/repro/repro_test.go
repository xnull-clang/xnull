package repro

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func mkfile(t *testing.T, dir, rel, body string) {
	t.Helper()
	p := filepath.Join(dir, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// S8-09：锁字节稳定（同一输入重复生成逐字节一致）。
func TestLockBytesStable(t *testing.T) {
	entries := []LockEntry{
		{Coordinate: "g:z", Version: "1.0.0", SHA256: strings.Repeat("a", 64)},
		{Coordinate: "g:a", Version: "2.0.0", SHA256: strings.Repeat("b", 64)},
		{Coordinate: "g:m", Version: "3.0.0", SHA256: strings.Repeat("c", 64)},
	}
	var first []byte
	for i := 0; i < 10; i++ {
		// 每次打乱输入顺序（map 迭代语义），输出必须稳定。
		perm := append([]LockEntry{}, entries...)
		for j := 0; j < i%3; j++ {
			perm[0], perm[len(perm)-1] = perm[len(perm)-1], perm[0]
		}
		p := filepath.Join(t.TempDir(), "xnull.lock")
		if err := WriteLockStable(p, perm); err != nil {
			t.Fatal(err)
		}
		data, _ := os.ReadFile(p)
		if i == 0 {
			first = data
			continue
		}
		if string(data) != string(first) {
			t.Fatalf("第 %d 次锁字节不稳定：\n%s\n---\n%s", i+1, first, data)
		}
	}
	if strings.Index(string(first), "entry g:a") > strings.Index(string(first), "entry g:z") {
		t.Fatalf("锁未按坐标升序：\n%s", first)
	}
}

// S8-09：输入清单穷举 + 稳定摘要。
func TestInputsDigest(t *testing.T) {
	dir := t.TempDir()
	mkfile(t, dir, "xnull.project", "project {}\n")
	mkfile(t, dir, "src/main/x/main.x", "static Int main() { return 0 }\n")

	in, err := CollectInputs(InputSpec{
		ProjectDir:  dir,
		Manifests:   []string{"xnull.project"},
		SourceRoots: []string{"src/main/x"},
		LockPath:    "xnull.lock",
		Toolchain:   "5.3.1",
		Platform:    "macos",
		Profiles:    []string{"dev", "ci"},
	})
	if err != nil {
		t.Fatal(err)
	}
	d1 := in.Digest()
	if d1 == "" {
		t.Fatal("摘要为空")
	}
	// 重复采集稳定（含 map 顺序）
	for i := 0; i < 5; i++ {
		in2, _ := CollectInputs(InputSpec{ProjectDir: dir, Manifests: []string{"xnull.project"},
			SourceRoots: []string{"src/main/x"}, LockPath: "xnull.lock", Toolchain: "5.3.1",
			Platform: "macos", Profiles: []string{"ci", "dev"}})
		if in2.Digest() != d1 {
			t.Fatalf("profile 顺序不应影响摘要")
		}
	}

	// 源码变更 → 摘要变化
	mkfile(t, dir, "src/main/x/main.x", "static Int main() { return 1 }\n")
	in3, _ := CollectInputs(InputSpec{ProjectDir: dir, Manifests: []string{"xnull.project"},
		SourceRoots: []string{"src/main/x"}, LockPath: "xnull.lock", Toolchain: "5.3.1",
		Platform: "macos", Profiles: []string{"dev", "ci"}})
	if in3.Digest() == d1 {
		t.Fatal("源码变更后摘要未变")
	}

	// 工具链/平台/profile/锁 任一变化 → 摘要变化
	base := InputSpec{ProjectDir: dir, Manifests: []string{"xnull.project"}, SourceRoots: []string{"src/main/x"},
		LockPath: "xnull.lock", Toolchain: "5.3.1", Platform: "macos", Profiles: []string{"dev"}}
	b, _ := CollectInputs(base)
	for name, mutate := range map[string]func(*InputSpec){
		"toolchain": func(s *InputSpec) { s.Toolchain = "6.0.0" },
		"platform":  func(s *InputSpec) { s.Platform = "linux" },
		"profiles":  func(s *InputSpec) { s.Profiles = []string{"dev", "extra"} },
	} {
		sp := base
		mutate(&sp)
		got, _ := CollectInputs(sp)
		if got.Digest() == b.Digest() {
			t.Fatalf("%s 变化后摘要未变", name)
		}
	}
}

// S8-09：两次构建摘要比对（同状态一致、变更即不同）。
func TestBuildSummaryCompare(t *testing.T) {
	dir := t.TempDir()
	mkfile(t, dir, "xnull.project", "project {}\n")
	mkfile(t, dir, "src/main/x/main.x", "static Int main() { return 0 }\n")
	mkfile(t, dir, "xnull.lock", "lock {\n  version = 1\n}\n")
	spec := InputSpec{ProjectDir: dir, Manifests: []string{"xnull.project"},
		SourceRoots: []string{"src/main/x"}, LockPath: "xnull.lock", Toolchain: "5.3.1", Platform: "macos"}

	a, err := Summary(spec)
	if err != nil {
		t.Fatal(err)
	}
	b, _ := Summary(spec)
	if !SameSummary(a, b) {
		t.Fatalf("同状态两次摘要应一致：%+v %+v", a, b)
	}

	mkfile(t, dir, "src/main/x/main.x", "static Int main() { return 2 }\n")
	c, _ := Summary(spec)
	if SameSummary(a, c) {
		t.Fatal("源码变更后摘要应不同")
	}

	// 锁变更 → 摘要不同
	mkfile(t, dir, "src/main/x/main.x", "static Int main() { return 0 }\n")
	mkfile(t, dir, "xnull.lock", "lock {\n  version = 1\n}\n# changed\n")
	d, _ := Summary(spec)
	if SameSummary(a, d) {
		t.Fatal("锁变更后摘要应不同")
	}
}

// S8-09：target 之外写入检测。
func TestCheckWritesOutsideTarget(t *testing.T) {
	dir := t.TempDir()
	mkfile(t, dir, "src/main/x/main.x", "a")
	mkfile(t, dir, "target/old.txt", "old")
	before, err := Snapshot(dir, []string{"target"})
	if err != nil {
		t.Fatal(err)
	}
	// target 内变更不算越界
	mkfile(t, dir, "target/new.txt", "new")
	mkfile(t, dir, "src/main/x/main.x", "b")
	after, _ := Snapshot(dir, []string{"target"})
	if ds := CheckWrites(before, after, dir); len(ds) != 1 || !strings.Contains(ds[0].Message, "src/main/x/main.x") {
		t.Fatalf("应只报 target 之外的写：%v", ds)
	}

	// 删除 target 外文件也算
	os.Remove(filepath.Join(dir, "src/main/x/main.x"))
	after2, _ := Snapshot(dir, []string{"target"})
	if ds := CheckWrites(after, after2, dir); len(ds) != 1 {
		t.Fatalf("删除应被检测：%v", ds)
	}
}
