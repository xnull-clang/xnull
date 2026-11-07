package xmeta

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/diag"
)

const goodMeta = `xmeta {
  groupId = com.example
  artifactId = demo
  version = 1.0.0
  packaging = app
  platform = darwin-arm64
  xdkVersion = 1.1.0
  languageVersion = 3.3.0
  toolchainVersion = 0.1.0-dev
  profiles = [dev]
  plugins = codegen
  lockSha256 = abc
  inputs = abc
}
`

func TestValidateGood(t *testing.T) {
	ds := Validate("demo.xmeta", goodMeta, "0.1.0-dev")
	if len(ds) != 0 {
		t.Fatalf("合法元数据不应报错：%v", ds)
	}
}

func TestValidateMissingField(t *testing.T) {
	src := strings.Replace(goodMeta, "  lockSha256 = abc\n", "", 1)
	ds := Validate("demo.xmeta", src, "0.1.0-dev")
	if !hasCode(ds, "XPD-701") {
		t.Fatalf("缺字段应报 XPD-701：%v", ds)
	}
}

func TestValidateToolchainMismatch(t *testing.T) {
	src := strings.Replace(goodMeta, "toolchainVersion = 0.1.0-dev", "toolchainVersion = 9.9.9", 1)
	ds := Validate("demo.xmeta", src, "0.1.0-dev")
	if !hasCode(ds, "XPD-703") {
		t.Fatalf("工具链版本不符应报 XPD-703：%v", ds)
	}
}

func TestValidateUnknownField(t *testing.T) {
	src := strings.Replace(goodMeta, "  packaging = app\n", "  packaging = app\n  nonsense = x\n", 1)
	ds := Validate("demo.xmeta", src, "0.1.0-dev")
	if !hasCode(ds, "XPD-702") {
		t.Fatalf("未知字段应报 XPD-702：%v", ds)
	}
}

func TestValidateBadRoot(t *testing.T) {
	ds := Validate("demo.xmeta", "project {\n}\n", "0.1.0-dev")
	if !hasCode(ds, "XPD-701") {
		t.Fatalf("根块不符应报 XPD-701：%v", ds)
	}
}

func hasCode(ds []diag.Diagnostic, code string) bool {
	for _, d := range ds {
		if d.Code == code {
			return true
		}
	}
	return false
}
