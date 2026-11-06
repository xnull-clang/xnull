package devtool

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// 资源名按段校验：每段只允许 [A-Za-z0-9_.-]，段间用单个 / 分隔。
// S8 §5.6：目录内全部常规文件按「相对资源根的路径」收录，因此子目录合法；
// 绝对路径、空段、. 与 .. 段一律拒绝（运行时同样禁止绝对路径与 .. 段）。
var resourceSegmentRe = regexp.MustCompile(`^[A-Za-z0-9_.\-]+$`)

type resourceEntry struct {
	name string
	data []byte
}

// GenerateResources 把资源目录生成为自包含 C 源文件（S8 §5.6）。
//
// 合同：
//   - 递归收录资源根下全部常规文件，资源名为相对资源根的 / 分隔路径（§5.6「收录」）；
//   - 按资源名升序输出，保证确定性；空目录不产生条目；
//   - 资源名按段非法（含空白、反斜杠）、绝对路径、. / .. 段、重复名、符号链接断链或越界时显式报错；
//   - 符号链接按目标内容读取（§5.6「符号链接」）；指向目录的链接拒绝（避免环）；
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

// collectResources 递归遍历资源根：先本层文件（名字升序），再逐个子目录。
// 这样首个错误的报告顺序与旧实现一致。
func collectResources(root string) ([]resourceEntry, error) {
	var entries []resourceEntry
	seen := make(map[string]bool)

	// 资源根本身可能位于符号链接路径下（如 macOS /tmp → /private/tmp），
	// 用真实路径做符号链接越界判断。
	rootReal, err := filepath.EvalSymlinks(root)
	if err != nil {
		return nil, fmt.Errorf("解析资源根失败：%v", err)
	}

	var walk func(dir string) error
	walk = func(dir string) error {
		items, err := os.ReadDir(dir) // 已按文件名排序
		if err != nil {
			return err
		}
		var subdirs []string
		for _, it := range items {
			path := filepath.Join(dir, it.Name())
			rel, err := filepath.Rel(root, path)
			if err != nil {
				return err
			}
			name := filepath.ToSlash(rel)

			if it.Type()&os.ModeSymlink != 0 {
				target, err := os.Stat(path) // 跟随链接，断链即失败
				if err != nil {
					return fmt.Errorf("符号链接断链：%s（%v）", name, err)
				}
				if target.IsDir() {
					return fmt.Errorf("符号链接指向目录（拒绝递归，避免环）：%s", name)
				}
				real, err := filepath.EvalSymlinks(path)
				if err != nil {
					return fmt.Errorf("符号链接断链：%s（%v）", name, err)
				}
				if !within(rootReal, real) {
					return fmt.Errorf("符号链接指向资源根之外：%s → %s", name, real)
				}
			} else if it.IsDir() {
				subdirs = append(subdirs, path)
				continue
			}

			if err := validateResourceName(name); err != nil {
				return err
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

// validateResourceName 校验「相对资源根的 / 分隔路径」。
func validateResourceName(name string) error {
	if name == "" {
		return fmt.Errorf("资源名为空")
	}
	if strings.HasPrefix(name, "/") || strings.HasSuffix(name, "/") {
		return fmt.Errorf("资源名不得以 / 开头或结尾：%s", name)
	}
	if strings.Contains(name, `\`) {
		return fmt.Errorf("资源名不得含反斜杠：%s", name)
	}
	for _, seg := range strings.Split(name, "/") {
		if seg == "" {
			return fmt.Errorf("资源名含空路径段：%s", name)
		}
		if seg == "." || seg == ".." {
			return fmt.Errorf("资源名含非法路径段 %q：%s", seg, name)
		}
		if !resourceSegmentRe.MatchString(seg) {
			return fmt.Errorf("资源名非法（每段限 [A-Za-z0-9_.-]）：%s", name)
		}
	}
	return nil
}

// within 判断 target 是否位于 root 之内（两者均应为解析过符号链接的绝对路径）。
func within(root, target string) bool {
	rel, err := filepath.Rel(root, target)
	if err != nil || filepath.IsAbs(rel) {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(os.PathSeparator))
}

// renderResources 生成 C 源文本。
//
// 首行保留迁移前的生成器署名文本，是为了与 Python golden 逐字节一致；
// 是否改为 `xnull dev res` 另行判定，不阻塞当前门。
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
