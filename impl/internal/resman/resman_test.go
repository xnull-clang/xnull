package resman

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/diag"
)

func mkfile(t *testing.T, dir, rel, body string) string {
	t.Helper()
	p := filepath.Join(dir, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func hasCode(ds []string, want string) bool {
	for _, c := range ds {
		if strings.HasPrefix(c, want) {
			return true
		}
	}
	return false
}

func codesOf(ds []diag.Diagnostic) []string {
	var out []string
	for _, d := range ds {
		out = append(out, d.Code)
	}
	return out
}

// S8-08：资源根 + includes/excludes glob + 制品前缀。
func TestCollectGlobAndPrefix(t *testing.T) {
	dir := t.TempDir()
	mkfile(t, dir, "a.txt", "A")
	mkfile(t, dir, "sub/x.txt", "X")
	mkfile(t, dir, "sub/y.psd", "Y")

	set, diags := Collect([]Root{{Path: dir, Includes: []string{"**"}, Excludes: []string{"**/*.psd"}}})
	if len(diags) != 0 {
		t.Fatalf("不应有诊断：%v", diags)
	}
	if _, ok := set.Entries["resources/a.txt"]; !ok {
		t.Fatalf("缺少 resources/a.txt：%v", keys(set))
	}
	if _, ok := set.Entries["resources/sub/x.txt"]; !ok {
		t.Fatalf("缺少 resources/sub/x.txt：%v", keys(set))
	}
	if _, ok := set.Entries["resources/sub/y.psd"]; ok {
		t.Fatalf("excludes 未生效：%v", keys(set))
	}

	set2, ds2 := Collect([]Root{{Path: dir, Includes: []string{"sub/**"}}})
	if len(ds2) != 0 {
		t.Fatalf("不应有诊断：%v", ds2)
	}
	if _, ok := set2.Entries["resources/sub/x.txt"]; !ok {
		t.Fatalf("includes 未生效：%v", keys(set2))
	}
	if _, ok := set2.Entries["resources/a.txt"]; ok {
		t.Fatalf("includes 外文件被收录：%v", keys(set2))
	}
}

func TestGlobSemantics(t *testing.T) {
	cases := []struct {
		pattern, path string
		want          bool
	}{
		{"**", "a/b/c.txt", true},
		{"sub/**", "sub/a/b.txt", true},
		{"sub/**", "other/a.txt", false},
		{"*.txt", "a.txt", true},
		{"*.txt", "sub/a.txt", false},
		{"?.txt", "a.txt", true},
		{"?.txt", "ab.txt", false},
		{"**/*.psd", "a/b/y.psd", true},
		{"**/*.psd", "y.psd", true}, // `**` 可消费零段
		{"images/**", "images/a/b.png", true},
	}
	for _, c := range cases {
		if got := Match(c.pattern, c.path); got != c.want {
			t.Fatalf("Match(%q,%q)=%v，期望 %v", c.pattern, c.path, got, c.want)
		}
	}
}

// S8-08：同路径冲突点名两个来源。
func TestConflictNamesBothSources(t *testing.T) {
	d1, d2 := t.TempDir(), t.TempDir()
	mkfile(t, d1, "templates/a.html", "one")
	mkfile(t, d2, "templates/a.html", "two")
	_, diags := Collect([]Root{
		{Path: d1, Includes: []string{"**"}},
		{Path: d2, Includes: []string{"**"}},
	})
	if len(diags) == 0 || !hasCode(codesOf(diags), "XPD-803") {
		t.Fatalf("应报 XPD-803：%v", diags)
	}
	msg := diags[0].Message
	if !strings.Contains(msg, d1) || !strings.Contains(msg, d2) {
		t.Fatalf("冲突诊断未点名两个来源：%s", msg)
	}
}

// S8-08：依赖资源合并 / starter 不合并。
func TestMergeDependency(t *testing.T) {
	appDir, depDir := t.TempDir(), t.TempDir()
	mkfile(t, appDir, "app.txt", "a")
	mkfile(t, depDir, "lib.txt", "l")
	app, _ := Collect([]Root{{Path: appDir, Includes: []string{"**"}, Owner: "g:app"}})
	dep, _ := Collect([]Root{{Path: depDir, Includes: []string{"**"}, Owner: "g:lib"}})

	merged, ds := MergeDependency(app, "g:lib", dep, "library")
	if len(ds) != 0 {
		t.Fatalf("不应有诊断：%v", ds)
	}
	if _, ok := merged.Entries["resources/lib.txt"]; !ok {
		t.Fatalf("依赖资源未合并：%v", keys(merged))
	}

	if _, ds := MergeDependency(app, "g:starter", dep, "starter"); len(ds) != 0 {
		t.Fatalf("starter 不应报错：%v", ds)
	}
	merged2, _ := MergeDependency(app, "g:starter", dep, "starter")
	if _, ok := merged2.Entries["resources/lib.txt"]; ok {
		t.Fatalf("starter 资源不应合并：%v", keys(merged2))
	}

	// 冲突点名两个 owner
	dep2Dir := t.TempDir()
	mkfile(t, dep2Dir, "app.txt", "conflict")
	dep2, _ := Collect([]Root{{Path: dep2Dir, Includes: []string{"**"}, Owner: "g:other"}})
	_, ds = MergeDependency(app, "g:other", dep2, "library")
	if !hasCode(codesOf(ds), "XPD-803") {
		t.Fatalf("依赖冲突应报 XPD-803：%v", ds)
	}
	if !strings.Contains(ds[0].Message, "g:app") || !strings.Contains(ds[0].Message, "g:other") {
		t.Fatalf("冲突未点名两个 groupId:artifactId：%s", ds[0].Message)
	}
}

// S8-08：符号链接跟随、断链失败。
func TestSymlinks(t *testing.T) {
	dir := t.TempDir()
	mkfile(t, dir, "real.txt", "content")
	if err := os.Symlink(filepath.Join(dir, "real.txt"), filepath.Join(dir, "alias.txt")); err != nil {
		t.Skipf("无法创建符号链接：%v", err)
	}
	set, ds := Collect([]Root{{Path: dir, Includes: []string{"**"}}})
	if len(ds) != 0 {
		t.Fatalf("不应有诊断：%v", ds)
	}
	if e, ok := set.Entries["resources/alias.txt"]; !ok || string(e.Data) != "content" {
		t.Fatalf("符号链接应按目标内容收录：%v", keys(set))
	}

	brokenDir := t.TempDir()
	if err := os.Symlink(filepath.Join(brokenDir, "gone.txt"), filepath.Join(brokenDir, "broken.txt")); err != nil {
		t.Skipf("无法创建符号链接：%v", err)
	}
	_, ds = Collect([]Root{{Path: brokenDir, Includes: []string{"**"}}})
	if !hasCode(codesOf(ds), "XPD-805") {
		t.Fatalf("断链应报 XPD-805：%v", ds)
	}
}

// S8-08：测试资源隔离 / 空目录 / pom 规则。
func TestPhaseAndPackaging(t *testing.T) {
	dir := t.TempDir()
	mkfile(t, dir, "main.txt", "m")
	testDir := t.TempDir()
	mkfile(t, testDir, "t.txt", "t")

	set, ds := CollectForPhase("main", []Root{{Path: dir, Includes: []string{"**"}}}, []Root{{Path: testDir, Includes: []string{"**"}}})
	if len(ds) != 0 {
		t.Fatalf("不应有诊断：%v", ds)
	}
	if _, ok := set.Entries["resources/main.txt"]; !ok {
		t.Fatalf("主资源缺失：%v", keys(set))
	}
	if _, ok := set.Entries["resources/t.txt"]; ok {
		t.Fatalf("测试资源不得进入产物：%v", keys(set))
	}
	setTest, _ := CollectForPhase("test", []Root{{Path: dir, Includes: []string{"**"}}}, []Root{{Path: testDir, Includes: []string{"**"}}})
	if _, ok := setTest.Entries["resources/t.txt"]; !ok {
		t.Fatalf("test 阶段应可见测试资源：%v", keys(setTest))
	}

	empty := t.TempDir()
	os.MkdirAll(filepath.Join(empty, "e", "n"), 0o755)
	setE, dsE := Collect([]Root{{Path: empty, Includes: []string{"**"}}})
	if len(dsE) != 0 || len(setE.Entries) != 0 {
		t.Fatalf("空目录不应产生条目：%v %v", dsE, keys(setE))
	}

	if _, dsP := CollectForPackaging("pom", []Root{{Path: dir, Includes: []string{"**"}}}); !hasCode(codesOf(dsP), "XPD-804") {
		t.Fatalf("pom 声明资源应失败：%v", dsP)
	}
}

func TestInvalidRootAndGlob(t *testing.T) {
	_, ds := Collect([]Root{{Path: filepath.Join(t.TempDir(), "nope")}})
	if !hasCode(codesOf(ds), "XPD-801") {
		t.Fatalf("资源根不存在应报 XPD-801：%v", ds)
	}
	dir := t.TempDir()
	mkfile(t, dir, "a.txt", "a")
	_, ds = Collect([]Root{{Path: dir, Includes: []string{"[ab].txt"}}})
	if !hasCode(codesOf(ds), "XPD-802") {
		t.Fatalf("字符类 glob 应报 XPD-802：%v", ds)
	}
}

func keys(s Set) []string {
	var out []string
	for k := range s.Entries {
		out = append(out, k)
	}
	return out
}
