package codegen

import (
	"os"
	"path/filepath"
	"testing"

	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// S6-07：xdk.collections 源码单元表面——4 个算法 + 4 个容器类。
func TestXdkCollectionsUnitSurface(t *testing.T) {
	path, err := filepath.Abs(filepath.Join("..", "..", "lib", "xdk", "collections.x"))
	if err != nil {
		t.Fatal(err)
	}
	src, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("读取 collections.x 失败：%v", err)
	}
	u, pdiags := xfront.ParseUnit(path, string(src))
	if len(pdiags) > 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}
	if sd := sema.Analyze(path, u); len(sd) > 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	if _, err := EmitC(u); err != nil {
		t.Fatalf("代码生成失败：%v", err)
	}
	funcs := map[string]bool{}
	classes := map[string]bool{}
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.TopFunc:
			funcs[n.Name] = true
		case *xfront.ClassDecl:
			classes[n.Name] = true
		}
	}
	for _, name := range []string{"sortBy", "dedup", "find", "groupByInt"} {
		if !funcs[name] {
			t.Fatalf("缺少算法函数 %s", name)
		}
	}
	for _, name := range []string{"RingBuffer", "OrderedMap", "BTreeMap", "PriorityQueue"} {
		if !classes[name] {
			t.Fatalf("缺少容器类 %s", name)
		}
	}
}
