package sema

import (
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- S3 P1-10：静态字段根登记 ----------

// StaticRoot 是一个全局/静态字段根，供 E4 生成 rt_gc_root_add、E5 校验根集合。
// Kind: global | singleton.static | singleton.instance | enum.field。
type StaticRoot struct {
	Decl  string `json:"decl"`
	Field string `json:"field"`
	Kind  string `json:"kind"`
	Type  string `json:"type"`
	GC    bool   `json:"gc"`
	Order int    `json:"order"`
	Line  int    `json:"line"`
	Col   int    `json:"col"`
}

// StaticRoots 按源码声明顺序输出根登记；确定性（DET-01）：不依赖 map 枚举。
func (r *Result) StaticRoots(u *xfront.CompilationUnit) []StaticRoot {
	out := []StaticRoot{}
	n := 0
	add := func(decl, field, kind string, t xfront.TypeRef, p xfront.Pos) {
		n++
		out = append(out, StaticRoot{Decl: decl, Field: field, Kind: kind,
			Type: typeKey(t), GC: r.a.staticRootIsGC(t), Order: n, Line: p.Line, Col: p.Col})
	}
	for _, d := range u.Decls {
		switch x := d.(type) {
		case *xfront.TopField:
			kind := "global"
			if x.Static {
				kind = "global.static"
			}
			add("<global>", x.Name, kind, x.Type, x.P)
		case *xfront.SingletonDecl:
			for _, f := range x.Fields {
				kind := "singleton.instance"
				if f.Mod.Static {
					kind = "singleton.static"
				}
				add(x.Name, f.Name, kind, f.Type, f.P)
			}
		case *xfront.EnumDecl:
			if x.IsData {
				for _, f := range x.Fields {
					add(x.Name, f.Name, "enum.field", f.Type, f.P)
				}
			}
		}
	}
	return out
}

func (a *analyzer) staticRootIsGC(t xfront.TypeRef) bool {
	key := typeKey(t)
	base := unwrapTypeKey(key)
	if base == "" || base == "void" {
		return false
	}
	if isIntType(base) || isFloatType(base) || base == "Bool" || base == "Char" {
		return false
	}
	switch base {
	case "String", "Text", "Bytes", "StringBuilder", "Any", "Object":
		return true
	}
	if strings.HasSuffix(base, "[]") || strings.HasPrefix(base, "List<") ||
		strings.HasPrefix(base, "Map<") || strings.HasPrefix(base, "Set<") ||
		strings.HasPrefix(base, "Result<") || strings.HasPrefix(base, "(") || strings.HasPrefix(base, "fn") {
		return true
	}
	if a.tc != nil {
		if info, ok := a.tc.types[base]; ok {
			switch info.kind {
			case "class", "protocol", "singleton", "annotation":
				return true
			case "enum":
				return info.enum != nil && info.enum.IsData
			case "struct":
				return false
			}
		}
	}
	return true // 未知/外部引用保守按 GC
}
