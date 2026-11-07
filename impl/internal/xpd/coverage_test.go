package xpd

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// S8-10b：核对 2xx—8xx 码位在实际校验器中的落点。
// 代码源扫描仅在该分支/工作树含 manifest/config/plugin/resman 时执行；
// 只含 xpd 的分支跳过（避免把“上游包未合入”误报为码位缺失）。
func TestS810bCodeCoverage(t *testing.T) {
	root := filepath.Join("..", "..", "..")
	for _, pkg := range []string{"manifest", "config", "plugin", "resman"} {
		if _, err := os.Stat(filepath.Join(root, "impl", "internal", pkg)); err != nil {
			t.Skip("上游校验器未合入当前分支（需 manifest/config/plugin/resman）")
		}
	}
	re := regexp.MustCompile(`XPD-[2-8][0-9][0-9]`)
	seen := map[string]bool{}
	err := filepath.WalkDir(filepath.Join(root, "impl", "internal"), func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		if strings.HasSuffix(path, filepath.Join("xpd", "diagcodes.go")) || strings.Contains(path, filepath.Join("internal", "diag")+string(filepath.Separator)) {
			return nil // 码表/诊断渲染器本身不算校验器落点
		}
		src, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		for _, m := range re.FindAllString(string(src), -1) {
			seen[m] = true
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, spec := range CodeSpecs {
		if spec.Code[4] < '2' || spec.Code[4] > '8' {
			continue
		}
		if !seen[spec.Code] {
			t.Errorf("%s (%s) 无校验器落点（S8-10b）", spec.Code, spec.Category)
		}
	}
	for code := range seen {
		if _, ok := CodeSpec(code); !ok {
			t.Errorf("校验器使用未登记码位 %s", code)
		}
	}
}
