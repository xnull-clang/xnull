package devtool

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// 资源名整体校验：只允许 [A-Za-z0-9_.-]，且**不含路径分隔符**。
// 注意：这与 S8 §5.6 的「允许资源子目录」不一致，是迁移期为满足
// 「同输入逐字节一致」而保留的既有行为；修正另行排期。
var resourceNameRe = regexp.MustCompile(`^[A-Za-z0-9_.\-]+$`)

type resourceEntry struct {
	name string
	data []byte
}

// GenerateResources 把资源目录生成为自包含 C 源文件（S8 §5.6）。
//
// 合同（与迁移前 gen_resources.py 一致）：
//   - 按资源名升序输出，保证确定性；
//   - 资源名非法或重复时显式报错；
//   - 空目录生成零成本空表；
//   - 只依赖 libc，供构建期链接。
func GenerateResources(srcDir, outPath string) error {
	info, err := os.Stat(srcDir)
	if err != nil || !info.IsDir() {
		return fmt.Errorf("资源目录不存在：%s", srcDir)
	}
	entries, err := collectResources(srcDir)
	if err != nil {
		return err
	}
	return os.WriteFile(outPath, []byte(renderResources(entries)), 0o644)
}

// collectResources 按 Python os.walk 的顺序遍历：先本层文件（名字升序），再逐个子目录。
// 这样首个错误的报告顺序与旧实现一致。
func collectResources(root string) ([]resourceEntry, error) {
	var entries []resourceEntry
	seen := make(map[string]bool)

	var walk func(dir string) error
	walk = func(dir string) error {
		items, err := os.ReadDir(dir) // 已按文件名排序
		if err != nil {
			return err
		}
		var subdirs []string
		for _, it := range items {
			path := filepath.Join(dir, it.Name())
			if it.IsDir() {
				subdirs = append(subdirs, path)
				continue
			}
			rel, err := filepath.Rel(root, path)
			if err != nil {
				return err
			}
			name := filepath.ToSlash(rel)
			if !resourceNameRe.MatchString(name) {
				return fmt.Errorf("资源名非法（限 [A-Za-z0-9_.-]）：%s", name)
			}
			if seen[name] {
				return fmt.Errorf("资源名重复：%s", name)
			}
			seen[name] = true
			data, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			entries = append(entries, resourceEntry{name: name, data: data})
		}
		for _, sub := range subdirs {
			if err := walk(sub); err != nil {
				return err
			}
		}
		return nil
	}

	if err := walk(root); err != nil {
		return nil, err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].name < entries[j].name })
	return entries, nil
}

// renderResources 生成 C 源文本。
//
// 首行保留迁移前的生成器署名文本，是为了与 Python golden 逐字节一致。
// 待资源子目录行为修正时一并更新。
func renderResources(entries []resourceEntry) string {
	var b strings.Builder
	b.WriteString("/* 由 impl/tools/gen_resources.py 生成（构建期产物，勿手改；S8 §5.6）。\n")
	b.WriteString(" * 资源表按名称升序；查找为二分；空表零成本。 */\n")
	b.WriteString("#include <stddef.h>\n")
	b.WriteString("#include <string.h>\n")
	b.WriteString("\n")
	b.WriteString("typedef struct {\n")
	b.WriteString("    const char         *name;\n")
	b.WriteString("    const unsigned char *data;\n")
	b.WriteString("    size_t              len;\n")
	b.WriteString("} xrt_resource;\n")
	b.WriteString("\n")

	if len(entries) == 0 {
		b.WriteString("/* 空表：无资源的工程零成本 */\n")
		b.WriteString("size_t xrt_resource_count(void) { return 0; }\n")
		b.WriteString("\n")
		b.WriteString("int xrt_resource_get(const char *name, size_t nlen,\n")
		b.WriteString("                     const unsigned char **out, size_t *out_len) {\n")
		b.WriteString("    (void)name; (void)nlen;\n")
		b.WriteString("    *out = 0; *out_len = 0;\n")
		b.WriteString("    return 1;\n")
		b.WriteString("}\n")
		return b.String()
	}

	b.WriteString("static const xrt_resource g_xrt_resources[] = {\n")
	for _, e := range entries {
		fmt.Fprintf(&b, "    /* %s（%d 字节） */\n", e.name, len(e.data))
		b.WriteString("    {\n")
		fmt.Fprintf(&b, "        .name = \"%s\",\n", e.name)
		b.WriteString("        .data = (const unsigned char[]){\n")
		writeCBytes(&b, e.data)
		b.WriteString("        },\n")
		fmt.Fprintf(&b, "        .len = %d,\n", len(e.data))
		b.WriteString("    },\n")
	}
	b.WriteString("};\n")
	b.WriteString("\n")
	b.WriteString("size_t xrt_resource_count(void) {\n")
	b.WriteString("    return sizeof(g_xrt_resources) / sizeof(g_xrt_resources[0]);\n")
	b.WriteString("}\n")
	b.WriteString("\n")
	b.WriteString("int xrt_resource_get(const char *name, size_t nlen,\n")
	b.WriteString("                     const unsigned char **out, size_t *out_len) {\n")
	b.WriteString("    size_t lo = 0, hi = xrt_resource_count();\n")
	b.WriteString("    while (lo < hi) {\n")
	b.WriteString("        size_t mid = lo + (hi - lo) / 2;\n")
	b.WriteString("        const xrt_resource *r = &g_xrt_resources[mid];\n")
	b.WriteString("        size_t min_len = nlen < strlen(r->name) ? nlen : strlen(r->name);\n")
	b.WriteString("        int cmp = memcmp(name, r->name, min_len);\n")
	b.WriteString("        if (cmp == 0) {\n")
	b.WriteString("            if (nlen == strlen(r->name)) {\n")
	b.WriteString("                *out = r->data; *out_len = r->len; return 0;\n")
	b.WriteString("            }\n")
	b.WriteString("            cmp = nlen < strlen(r->name) ? -1 : 1;\n")
	b.WriteString("        }\n")
	b.WriteString("        if (cmp < 0) { hi = mid; } else { lo = mid + 1; }\n")
	b.WriteString("    }\n")
	b.WriteString("    return 1; /* 未找到：显式区分，不静默给空 */\n")
	b.WriteString("}\n")
	return b.String()
}

// writeCBytes 每行 16 字节、大写十六进制、行尾逗号（与旧实现逐字节一致）。
func writeCBytes(b *strings.Builder, data []byte) {
	for i := 0; i < len(data); i += 16 {
		end := i + 16
		if end > len(data) {
			end = len(data)
		}
		b.WriteString("    ")
		for j, c := range data[i:end] {
			if j > 0 {
				b.WriteString(", ")
			}
			fmt.Fprintf(b, "0x%02X", c)
		}
		b.WriteString(",\n")
	}
}
