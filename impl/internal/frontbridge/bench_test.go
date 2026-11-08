package frontbridge

import (
	"os"
	"path/filepath"
	"testing"
)

// BenchmarkParseUnitCorpus 量化前端解析开销（auto 不应显著高于 go）。
func BenchmarkParseUnitCorpus(b *testing.B) {
	root := repoRoot(b)
	var files []string
	for _, p := range corpusSources(b) {
		if filepath.Base(filepath.Dir(p)) == "corpus" || true {
			files = append(files, p)
		}
	}
	_ = root
	if len(files) == 0 {
		b.Fatal("语料为空")
	}
	// 取 8 个代表文件，覆盖 expr/stmt/decl/插值/容器。
	if len(files) > 8 {
		step := len(files) / 8
		var pick []string
		for i := 0; i < len(files); i += step {
			pick = append(pick, files[i])
			if len(pick) == 8 {
				break
			}
		}
		files = pick
	}
	type item struct{ name, src string }
	var items []item
	for _, p := range files {
		src, err := os.ReadFile(p)
		if err != nil {
			b.Fatal(err)
		}
		items = append(items, item{name: p, src: string(src)})
	}
	for _, mode := range []string{"go", "auto"} {
		b.Run(mode, func(b *testing.B) {
			b.Setenv("XNULL_FRONTEND", mode)
			b.Setenv("XNULL_NATIVE_XPARSER", "")
			b.Setenv("XNULL_SELFHOST_BIN", "")
			b.Setenv("XNULL_BIN", "")
			b.Setenv("XNULL_FRONTEND_AUTOBUILD", "0")
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				for _, it := range items {
					_, _ = ParseUnit(it.name, it.src)
				}
			}
		})
	}
}
