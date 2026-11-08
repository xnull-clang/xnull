package artifact

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func mk(t *testing.T, root, rel, body string) string {
	t.Helper()
	p := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func spec(t *testing.T, root string) Spec {
	t.Helper()
	mk(t, root, "xnull.project", "project {\n  groupId = g\n  artifactId = lib\n  version = 1.0.0\n  packaging = library\n}\n")
	mk(t, root, "src/main/x/lib.x", "static Int f() {\n    return 1\n}\n")
	mk(t, root, "src/main/resources/r.txt", "res\n")
	mk(t, root, "xnull.lock", "lock {\n  version = 1\n}\n")
	return Spec{
		Root: root, GroupID: "com.example", ArtifactID: "lib", Version: "1.0.0",
		Packaging: "library", ManifestPath: filepath.Join(root, "xnull.project"),
		SourceRoot: "src/main/x", ResourceDirs: []string{"src/main/resources"},
		LockPath:     filepath.Join(root, "xnull.lock"),
		Dependencies: []Dependency{{Coordinate: "g:dep", Version: "2.0.0"}},
	}
}

func TestXlibDeterministicAndContents(t *testing.T) {
	root := t.TempDir()
	sp := spec(t, root)
	var first Info
	for i := 0; i < 3; i++ {
		out := filepath.Join(t.TempDir(), XlibName("lib", "1.0.0"))
		info, ds, err := Build(sp, out)
		if err != nil || len(ds) > 0 {
			t.Fatalf("打包失败：%v %v", err, ds)
		}
		if i == 0 {
			first = info
		} else if info.SHA256 != first.SHA256 {
			t.Fatalf("第 %d 次 .xlib 字节不稳定", i+1)
		}
	}

	data, err := os.ReadFile(first.Path)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(data)
	if hex.EncodeToString(sum[:]) != first.SHA256 {
		t.Fatalf("返回摘要与实际字节不符")
	}
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		t.Fatal(err)
	}
	found := map[string]bool{}
	for _, f := range zr.File {
		found[f.Name] = true
	}
	for _, want := range []string{"xlib.meta", "xnull.project", "xnull.lock", "src/main/x/lib.x", "src/main/resources/r.txt"} {
		if !found[want] {
			t.Fatalf(".xlib 缺少条目 %q：%v", want, found)
		}
	}
	// 元数据含依赖与逐文件哈希
	var meta strings.Builder
	for _, f := range zr.File {
		if f.Name != "xlib.meta" {
			continue
		}
		rc, _ := f.Open()
		buf := new(bytes.Buffer)
		buf.ReadFrom(rc)
		rc.Close()
		meta.WriteString(buf.String())
	}
	for _, want := range []string{"dependency g:dep 2.0.0", "src/main/x/lib.x"} {
		if !strings.Contains(meta.String(), want) {
			t.Fatalf("xlib.meta 缺少 %q：\n%s", want, meta.String())
		}
	}
}

func TestInstallLayout(t *testing.T) {
	root := t.TempDir()
	sp := spec(t, root)
	out := filepath.Join(root, "target", XlibName("lib", "1.0.0"))
	if _, _, err := Build(sp, out); err != nil {
		t.Fatal(err)
	}
	repo := t.TempDir()
	installed, err := Install(repo, sp, out)
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(repo, "com", "example", "lib", "1.0.0", "lib-1.0.0.xlib")
	if installed != want {
		t.Fatalf("安装路径=%s，期望 %s", installed, want)
	}
	if _, err := os.Stat(want); err != nil {
		t.Fatalf("缺少已安装 .xlib：%v", err)
	}
	if _, err := os.Stat(filepath.Join(repo, "com", "example", "lib", "1.0.0", "xnull.project")); err != nil {
		t.Fatalf("缺少已安装清单：%v", err)
	}
}

func TestRemoteStub(t *testing.T) {
	if ErrRemoteUnimplemented == nil {
		t.Fatal("远程仓库应保留明确未实现错误")
	}
}
