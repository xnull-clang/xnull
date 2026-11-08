package cli

import (
	"bytes"
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/exitcode"
)

// B3-08b：AST bundle 覆盖 import 闭包且依赖后序。
func TestB308bASTBundle(t *testing.T) {
	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	entry := filepath.Join(root, "tests", "b2", "corpus", "examples", "multi", "main.x")
	var out, errb bytes.Buffer
	code := Run(Env{Stdout: &out, Stderr: &errb, Args: []string{"--emit-ast-bundle", entry}})
	if code != exitcode.Success {
		t.Fatalf("exit=%d stderr=%s", code, errb.String())
	}
	var got struct {
		Version string `json:"version"`
		Files   []struct {
			Path string `json:"path"`
			AST  string `json:"ast"`
		} `json:"files"`
	}
	if err := json.Unmarshal(out.Bytes(), &got); err != nil {
		t.Fatalf("JSON: %v", err)
	}
	if got.Version != "xnast-bundle v1" {
		t.Fatalf("version=%q", got.Version)
	}
	var names []string
	for _, f := range got.Files {
		names = append(names, filepath.Base(f.Path))
		if !strings.HasPrefix(f.AST, "(xnast v1 ") {
			t.Fatalf("%s AST 前缀不符：%q", f.Path, f.AST[:min(20, len(f.AST))])
		}
	}
	want := []string{"shapes.x", "text.x", "main.x"}
	if strings.Join(names, ",") != strings.Join(want, ",") {
		t.Fatalf("顺序=%v，期望 %v", names, want)
	}

	// XDK import 闭包：xdk.text/sync/tasks/collections 及其传递依赖都在，入口最后。
	fixture := filepath.Join(root, "tests", "b3", "fixtures", "bundle", "app.x")
	out.Reset()
	errb.Reset()
	if code := Run(Env{Stdout: &out, Stderr: &errb, Args: []string{"--emit-ast-bundle", fixture}}); code != 0 {
		t.Fatalf("fixture exit=%d stderr=%s", code, errb.String())
	}
	got.Files = nil
	if err := json.Unmarshal(out.Bytes(), &got); err != nil {
		t.Fatalf("JSON: %v", err)
	}
	names = nil
	for _, f := range got.Files {
		names = append(names, filepath.ToSlash(f.Path))
	}
	for _, want := range []string{"impl/lib/xdk/text.x", "impl/lib/xdk/sync.x", "impl/lib/xdk/tasks.x", "impl/lib/xdk/collections.x", "app.x"} {
		found := false
		for _, n := range names {
			if strings.HasSuffix(n, want) {
				found = true
			}
		}
		if !found {
			t.Fatalf("闭包缺 %s：%v", want, names)
		}
	}
	if !strings.HasSuffix(names[len(names)-1], "app.x") {
		t.Fatalf("入口应在最后：%v", names)
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
