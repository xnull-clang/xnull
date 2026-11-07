package xmeta

import (
	"sort"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/xpd"
)

// S8-10b：`.xmeta` 元数据校验（XPD-7xx）。
// 必需字段与语义见 S8 §5.3；本项目只做字段存在性/形态/工具链版本检查，
// 产物生成与摘要计算归 S8-04/09。

// Required 是 .xmeta 必需字段（S8 §5.3）。
var Required = []string{
	"groupId", "artifactId", "version", "packaging", "platform",
	"xdkVersion", "languageVersion", "toolchainVersion",
	"profiles", "plugins", "lockSha256", "inputs",
}

// Validate 校验 .xmeta 文本；toolchainVersion 为当前工具链版本。
func Validate(path, src, toolchainVersion string) []diag.Diagnostic {
	f, ds := xpd.Parse(path, src)
	if len(ds) > 0 {
		return ds
	}
	root := f.Find("xmeta")
	if root == nil {
		root = f.Find("plugin") // 兼容早期元数据根名；字段集合相同
	}
	if root == nil {
		return []diag.Diagnostic{xpd.NewDiag(path, xpd.Pos{Line: 1, Col: 1}, "XPD-701", "xmeta",
			"根块（xmeta/plugin）")}
	}

	fields := map[string]*xpd.Field{}
	for _, ch := range root.Children {
		if fld, ok := ch.(*xpd.Field); ok {
			fields[fld.Name] = fld
		}
	}
	var out []diag.Diagnostic
	for _, name := range Required {
		fld, ok := fields[name]
		if !ok {
			out = append(out, xpd.NewDiag(path, root.Pos, "XPD-701", "xmeta/"+name, name))
			continue
		}
		if fld.Value.Kind == xpd.ListValue && name != "profiles" {
			out = append(out, xpd.NewDiag(path, fld.Pos, "XPD-702", "xmeta/"+name, name))
		}
	}
	if fld, ok := fields["toolchainVersion"]; ok {
		got := fld.Value.Text
		if got != "" && toolchainVersion != "" && got != toolchainVersion {
			out = append(out, xpd.NewDiag(path, fld.Pos, "XPD-703", "xmeta/toolchainVersion",
				got+" != "+toolchainVersion))
		}
	}
	// 未知字段：.xmeta 只接受 §5.3 列出的字段。
	known := map[string]bool{}
	for _, n := range Required {
		known[n] = true
	}
	for name, node := range fields {
		if !known[name] {
			out = append(out, xpd.NewDiag(path, node.Position(), "XPD-702", "xmeta/"+name, name))
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Line != out[j].Line {
			return out[i].Line < out[j].Line
		}
		if out[i].Col != out[j].Col {
			return out[i].Col < out[j].Col
		}
		return out[i].Code < out[j].Code
	})
	return out
}
