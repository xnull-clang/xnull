package main

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func writeTemp(t *testing.T, dir, name, content string, mode os.FileMode) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(content), mode); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestRunFormatsInPlace(t *testing.T) {
	dir := t.TempDir()
	p := writeTemp(t, dir, "a.x", "static Int main(){\nreturn 0\n}\n", 0o640)
	var out, errb bytes.Buffer
	if code := run([]string{p}, &out, &errb); code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, errb.String())
	}
	got, _ := os.ReadFile(p)
	want := "static Int main() {\n    return 0\n}\n"
	if string(got) != want {
		t.Fatalf("格式化结果不符：%q", got)
	}
	info, _ := os.Stat(p)
	if info.Mode().Perm() != 0o640 {
		t.Fatalf("权限位未保留：%v", info.Mode().Perm())
	}
}

func TestRunCheckThreeStates(t *testing.T) {
	dir := t.TempDir()
	bad := writeTemp(t, dir, "bad.x", "static Int main(){\nreturn 0\n}\n", 0o644)
	good := writeTemp(t, dir, "good.x", "static Int main() {\n    return 0\n}\n", 0o644)

	var out, errb bytes.Buffer
	if code := run([]string{"--check", bad, good}, &out, &errb); code != 1 {
		t.Fatalf("有差异应退出 1，实际 %d", code)
	}
	data, _ := os.ReadFile(bad)
	if string(data) != "static Int main(){\nreturn 0\n}\n" {
		t.Fatalf("--check 不得写文件")
	}
	if code := run([]string{"--check", good}, &out, &errb); code != 0 {
		t.Fatalf("全规范应退出 0，实际 %d", code)
	}
}

func TestRunErrors(t *testing.T) {
	dir := t.TempDir()
	var out, errb bytes.Buffer
	if code := run(nil, &out, &errb); code != 2 {
		t.Fatalf("无参数应退出 2，实际 %d", code)
	}
	if code := run([]string{dir}, &out, &errb); code != 2 {
		t.Fatalf("目录参数应退出 2，实际 %d", code)
	}
}

func TestRunAtomicBatch(t *testing.T) {
	dir := t.TempDir()
	okFile := writeTemp(t, dir, "ok.x", "static Int main(){\nreturn 0\n}\n", 0o644)
	badFile := writeTemp(t, dir, "bad.x", "static String f() {\nreturn \"x\n}\n", 0o644)

	var out, errb bytes.Buffer
	if code := run([]string{okFile, badFile}, &out, &errb); code != 2 {
		t.Fatalf("词法错误应退出 2，实际 %d", code)
	}
	data, _ := os.ReadFile(okFile)
	if string(data) != "static Int main(){\nreturn 0\n}\n" {
		t.Fatalf("批处理不原子：合法文件被写入")
	}
	if errb.Len() == 0 {
		t.Fatalf("错误应写 stderr")
	}
}
