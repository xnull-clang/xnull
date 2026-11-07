package xpd

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/diag"
)

// S8-10：XPD-2xx—8xx 码位、固定类别/文案模板、段落路径。
func TestS810CodeRegistry(t *testing.T) {
	if len(CodeSpecs) == 0 {
		t.Fatal("码位表为空")
	}
	seen := map[string]bool{}
	for _, spec := range CodeSpecs {
		if seen[spec.Code] {
			t.Errorf("重复码位 %s", spec.Code)
		}
		seen[spec.Code] = true
		if len(spec.Code) != 7 || !strings.HasPrefix(spec.Code, "XPD-") {
			t.Errorf("码位形态非法：%s", spec.Code)
		}
		seg := spec.Code[4]
		want := map[byte]string{'2': "段落与字段", '3': "坐标与继承", '4': "依赖与锁", '5': "插件", '6': "配置", '7': "元数据", '8': "资源与打包"}[seg]
		if want == "" {
			t.Errorf("码位不在 2xx—8xx：%s", spec.Code)
			continue
		}
		if spec.Category != want {
			t.Errorf("%s 类别=%q，期望 %q", spec.Code, spec.Category, want)
		}
		if spec.Template == "" {
			t.Errorf("%s 缺文案模板", spec.Code)
		}
		if got := NewDiag("xnull.project", Pos{Line: 3, Col: 5}, spec.Code, "project/x", "v"); got.Code != spec.Code {
			t.Errorf("NewDiag 码位=%s", got.Code)
		}
	}

	d := NewDiag("xnull.project", Pos{Line: 12, Col: 3}, "XPD-202",
		"project/dependencies/dependency[2]/optional", "optonal")
	if d.Line != 12 || d.Col != 3 || !strings.Contains(d.Message, "optonal") {
		t.Fatalf("诊断字段不符：%+v", d)
	}
	if d.Path != "project/dependencies/dependency[2]/optional" {
		t.Fatalf("段落路径=%q", d.Path)
	}
	text := diag.Diagnostic(d).String()
	if !strings.Contains(text, "project/dependencies/dependency[2]/optional") {
		t.Fatalf("渲染缺少段落路径：%s", text)
	}
}

func TestS810NoUnknownSegment(t *testing.T) {
	for _, code := range []string{"XPD-201", "XPD-301", "XPD-401", "XPD-501", "XPD-601", "XPD-701", "XPD-801"} {
		if _, ok := CodeSpec(code); !ok {
			t.Errorf("缺段位代表码 %s", code)
		}
	}
}
