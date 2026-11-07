package xpd

import (
	"strings"
	"testing"
)

// S8-10：xnull fmt 的 XPD 规范化（清单/锁/元数据共用文法）。
func TestS810FormatSource(t *testing.T) {
	src := `project com.example:demo 1.0.0 {
groupId = com.example
    artifactId = demo
 # 保留注释
build {
mode = app
      sourceRoot = src/main/x
}
}
`
	want := `project com.example:demo 1.0.0 {
  groupId = com.example
  artifactId = demo
  # 保留注释
  build {
    mode = app
    sourceRoot = src/main/x
  }
}
`
	got, ds := FormatSource("xnull.project", src)
	if len(ds) != 0 {
		t.Fatalf("格式化诊断：%v", ds)
	}
	if got != want {
		t.Fatalf("格式化不符：\n got=%q\nwant=%q", got, want)
	}
	if again, ds := FormatSource("xnull.project", got); len(ds) != 0 || again != got {
		t.Fatalf("二次格式化不稳定：%v\n%q", ds, again)
	}
}

func TestS810FormatLockAndMeta(t *testing.T) {
	lock := `lock {
version = 1
entry com.example:common 1.4.0 {
kind = dependency
sha256 = 0000
}
}
`
	got, ds := FormatSource("xnull.lock", lock)
	if len(ds) != 0 {
		t.Fatalf("锁格式诊断：%v", ds)
	}
	if !strings.Contains(got, "\n  entry com.example:common 1.4.0 {\n    kind = dependency\n") {
		t.Fatalf("锁缩进不符：%q", got)
	}

	meta := `plugin com.example:demo 1.0.0 {
groupId = com.example
}
`
	if _, ds := FormatSource("xnull.xmeta", meta); len(ds) != 0 {
		t.Fatalf("元数据格式诊断：%v", ds)
	}
}

func TestS810FormatRejectsSyntax(t *testing.T) {
	_, ds := FormatSource("xnull.project", "project {\n  a =\n}\n")
	if len(ds) == 0 {
		t.Fatal("语法错误应返回诊断")
	}
	if !strings.HasPrefix(ds[0].Code, "XPD-1") && !strings.HasPrefix(ds[0].Code, "XPD-0") {
		t.Fatalf("语法诊断码异常：%s", ds[0].Code)
	}
}
