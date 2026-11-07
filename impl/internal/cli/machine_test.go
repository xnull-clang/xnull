package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"xnull.dev/xnull/internal/exitcode"
)

func runJSON(t *testing.T, args ...string) (int, string, string) {
	t.Helper()
	var out, errb bytes.Buffer
	code := Run(Env{Stdout: &out, Stderr: &errb, Args: args})
	return code, out.String(), errb.String()
}

func TestNewProjectJSON(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "demo")
	code, out, errOut := runJSON(t, "new", "app", dir, "--json")
	if code != exitcode.Success {
		t.Fatalf("exit=%d stderr=%s", code, errOut)
	}
	var res newJSONResult
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		t.Fatalf("JSON 解析失败：%v\n%s", err, out)
	}
	if !res.OK || res.Template != "app" || res.Directory != dir {
		t.Fatalf("结果不符：%+v", res)
	}
	for _, name := range []string{"xnull.project", "src/main/x/main.x", ".gitignore"} {
		if _, err := os.Stat(filepath.Join(dir, filepath.FromSlash(name))); err != nil {
			t.Fatalf("缺少 %s：%v", name, err)
		}
	}
	// 非空目录必须拒绝。
	code, out, _ = runJSON(t, "new", "app", dir, "--json")
	if code == exitcode.Success {
		t.Fatalf("非空目录不应成功：%s", out)
	}
	var bad newJSONResult
	_ = json.Unmarshal([]byte(out), &bad)
	if bad.OK || bad.Error == "" {
		t.Fatalf("失败结果不完整：%+v", bad)
	}
}

func TestCheckJSON(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "bad.x")
	src := "static Int main() {\n    Int x = \"s\"\n    return 0\n}\n"
	if err := os.WriteFile(path, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	code, out, errOut := runJSON(t, "check", path, "--json")
	if code != exitcode.BuildFail {
		t.Fatalf("exit=%d stderr=%s", code, errOut)
	}
	var res checkJSONResult
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		t.Fatalf("JSON 解析失败：%v\n%s", err, out)
	}
	if res.OK || len(res.Diagnostics) == 0 {
		t.Fatalf("应返回诊断：%+v", res)
	}
	if res.Diagnostics[0].Code == "" || res.Diagnostics[0].File == "" {
		t.Fatalf("诊断字段不完整：%+v", res.Diagnostics[0])
	}
}
