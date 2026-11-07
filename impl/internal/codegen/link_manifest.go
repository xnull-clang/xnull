// link_manifest.go — S8-07：清单 link.libraries 读取、FFI 区域交叉校验与链接参数合并。
package codegen

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/codegen/ffi"
	"xnull.dev/xnull/internal/xpd"
)

// readLinkLibraries 读取 root/xnull.project 的 project.link.libraries（S8 §7）。
// has 报告是否存在 libraries 块；不存在时不参与 FFI 交叉校验（bootstrap 兼容）。
func readLinkLibraries(root string) (libs []ffi.LinkLib, has bool, err error) {
	path := filepath.Join(root, projectManifest)
	src, rerr := os.ReadFile(path)
	if rerr != nil {
		if os.IsNotExist(rerr) {
			return nil, false, nil
		}
		return nil, false, fmt.Errorf("读取工程清单 %s：%w", path, rerr)
	}
	f, errs := xpd.Parse(projectManifest, string(src))
	if len(errs) > 0 {
		return nil, false, fmt.Errorf("工程清单 %s 解析失败：%s", path, errs[0])
	}
	proj := f.Find("project")
	if proj == nil {
		return nil, false, fmt.Errorf("工程清单 %s 缺少 project 块（S8 §3.2）", path)
	}
	packaging := ""
	for _, n := range proj.Children {
		if fld, ok := n.(*xpd.Field); ok && fld.Name == "packaging" {
			packaging = fld.Value.Text
		}
	}
	link := findChildBlock(proj, "link")
	if link == nil {
		return nil, false, nil
	}
	if packaging != "" && packaging != "app" && packaging != "library" && len(link.Children) > 0 {
		return nil, false, fmt.Errorf("packaging=%s 不得声明非空 link（S8 §7）", packaging)
	}
	for _, n := range link.Children {
		fld, isField := n.(*xpd.Field)
		if isField && fld.Name == "unsafe" {
			continue
		}
		if b, ok := n.(*xpd.Block); ok && b.Name == "libraries" {
			continue
		}
		return nil, false, fmt.Errorf("工程清单 %s 的 link 含未知字段/块（S8 §7）", path)
	}
	block := findChildBlock(link, "libraries")
	if block == nil {
		return nil, false, nil
	}
	seen := map[string]bool{}
	for _, n := range block.Children {
		b, ok := n.(*xpd.Block)
		if !ok || b.Name != "library" {
			return nil, false, fmt.Errorf("工程清单 %s 的 libraries 只能包含 library 块（S8 §7）", path)
		}
		if len(b.Args) != 1 || strings.TrimSpace(b.Args[0].Text) == "" {
			return nil, false, fmt.Errorf("工程清单 %s 的 library 缺少库名（S8 §7）", path)
		}
		name := b.Args[0].Text
		if seen[name] {
			return nil, false, fmt.Errorf("工程清单 %s 的 library %s 重复声明（S8 §7）", path, name)
		}
		seen[name] = true
		kind := ""
		system := false
		for _, cn := range b.Children {
			fld, ok := cn.(*xpd.Field)
			if !ok {
				return nil, false, fmt.Errorf("工程清单 %s 的 library %s 含未知子块（S8 §7）", path, name)
			}
			switch fld.Name {
			case "kind":
				if fld.Value.Kind != xpd.BareValue {
					return nil, false, fmt.Errorf("library %s 的 kind 必须是裸词 static/dynamic（S8 §7）", name)
				}
				kind = fld.Value.Text
			case "system":
				if fld.Value.Kind != xpd.BareValue {
					return nil, false, fmt.Errorf("library %s 的 system 必须是 true/false（S8 §7）", name)
				}
				switch fld.Value.Text {
				case "true":
					system = true
				case "false":
					system = false
				default:
					return nil, false, fmt.Errorf("library %s 的 system 值 %q 非法（限 true/false，S8 §7）", name, fld.Value.Text)
				}
			default:
				return nil, false, fmt.Errorf("library %s 含未知字段 %s（S8 §7）", name, fld.Name)
			}
		}
		if kind != "static" && kind != "dynamic" {
			return nil, false, fmt.Errorf("library %s 的 kind 必须是 static/dynamic（S8 §7）", name)
		}
		libs = append(libs, ffi.LinkLib{Name: name, Kind: kind, System: system})
	}
	sort.Slice(libs, func(i, j int) bool { return libs[i].Name < libs[j].Name })
	return libs, true, nil
}

// isInternalFFIRegion 判断 .xfb 区域是否属于工具链内部运行时（xdkc_*/xrt_*），
// 这类区域由运行时 C 源直接链接，不需要 link.libraries 声明。
func isInternalFFIRegion(region string) bool {
	return region == "" || strings.HasPrefix(region, "xdkc_") || strings.HasPrefix(region, "xrt_")
}

// checkFFILibraries 校验 FFI 注册表中的外部区域均已在 link.libraries 声明（S8 §7）。
// hasLibraries 为 false 时跳过（兼容尚无 link.libraries 的旧工程/测试夹具）。
func checkFFILibraries(reg *ffi.Registry, libs []ffi.LinkLib, hasLibraries bool) error {
	if reg == nil || !hasLibraries {
		return nil
	}
	declared := map[string]bool{}
	for _, l := range libs {
		if l.Name != "" {
			declared[l.Name] = true
		}
	}
	var missing []string
	for _, e := range reg.Entries {
		if isInternalFFIRegion(e.Region) {
			continue
		}
		if !declared[e.Region] {
			missing = append(missing, fmt.Sprintf("%s（入口 %s）", e.Region, e.Name))
		}
	}
	if len(missing) == 0 {
		return nil
	}
	sort.Strings(missing)
	return fmt.Errorf("FFI 绑定引用了未在 link.libraries 声明的库/区域：%s（S8 §7）",
		strings.Join(missing, ", "))
}

// mergeLinkArgs 把清单库合并进既有链接参数：-L 在前、-l 去重升序。
func mergeLinkArgs(base []string, libs []ffi.LinkLib) []string {
	var dirs []string
	names := map[string]bool{}
	for _, a := range base {
		switch {
		case strings.HasPrefix(a, "-L"):
			dirs = append(dirs, a)
		case strings.HasPrefix(a, "-l"):
			names[strings.TrimPrefix(a, "-l")] = true
		default:
			dirs = append(dirs, a)
		}
	}
	for _, l := range libs {
		if l.Name != "" {
			names[l.Name] = true
		}
	}
	sort.Strings(dirs)
	out := append([]string{}, dirs...)
	keys := make([]string, 0, len(names))
	for n := range names {
		keys = append(keys, n)
	}
	sort.Strings(keys)
	for _, n := range keys {
		out = append(out, "-l"+n)
	}
	return out
}
