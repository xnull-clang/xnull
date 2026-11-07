// unsafe_gate.go：S7-04 @unsafe 构建门禁（S7 §8 / S8 §7）。
package codegen

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"xnull.dev/xnull/internal/codegen/ffi"
	"xnull.dev/xnull/internal/xpd"
)

const projectManifest = "xnull.project"

// findProjectRoot 从 start 向上查找 xnull.project；找不到返回空串。
func findProjectRoot(start string) string {
	dir, err := filepath.Abs(start)
	if err != nil {
		return ""
	}
	for {
		if st, err := os.Stat(filepath.Join(dir, projectManifest)); err == nil && !st.IsDir() {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}

// readLinkUnsafe 读取 root/xnull.project 的 project.link.unsafe（S8 §7）。
// found 报告清单是否存在；缺省 link/unsafe 视为 false（规范缺省值）。
func readLinkUnsafe(root string) (enabled, found bool, err error) {
	path := filepath.Join(root, projectManifest)
	src, rerr := os.ReadFile(path)
	if rerr != nil {
		if os.IsNotExist(rerr) {
			return false, false, nil
		}
		return false, true, fmt.Errorf("读取工程清单 %s：%w", path, rerr)
	}
	f, errs := xpd.Parse(projectManifest, string(src))
	if len(errs) > 0 {
		return false, true, fmt.Errorf("工程清单 %s 解析失败：%s", path, errs[0])
	}
	proj := f.Find("project")
	if proj == nil {
		return false, true, fmt.Errorf("工程清单 %s 缺少 project 块（S8 §3.2）", path)
	}
	link := findChildBlock(proj, "link")
	if link == nil {
		return false, true, nil
	}
	seen := false
	for _, n := range link.Children {
		fld, ok := n.(*xpd.Field)
		if !ok || fld.Name != "unsafe" {
			continue
		}
		if seen {
			return false, true, fmt.Errorf("工程清单 %s 的 link.unsafe 重复声明（S8 §3.2）", path)
		}
		seen = true
		if fld.Value.Kind != xpd.BareValue {
			return false, true, fmt.Errorf("工程清单 %s 的 link.unsafe 必须是 true/false（S8 §7）", path)
		}
		switch fld.Value.Text {
		case "true":
			enabled = true
		case "false":
			enabled = false
		default:
			return false, true, fmt.Errorf("工程清单 %s 的 link.unsafe 值 %q 非法（限 true/false，S8 §7）", path, fld.Value.Text)
		}
	}
	return enabled, true, nil
}

func findChildBlock(b *xpd.Block, name string) *xpd.Block {
	if b == nil {
		return nil
	}
	for _, n := range b.Children {
		if cb, ok := n.(*xpd.Block); ok && cb.Name == name {
			return cb
		}
	}
	return nil
}

// checkUnsafeGate 对构建中的 @unsafe 受控入口做门禁（S7 §8 / FFI-04）：
//
//  1. 声明层已由 ffi.Load 校验「仅 bindings/」与合同文本必填；
//  2. 工程清单必须存在且 link.unsafe = true（缺省 false，S8 §7）；
//  3. 启用后构建日志必须记录（规范强制，写 stderr）。
func checkUnsafeGate(entryDir string, reg *ffi.Registry, stderr io.Writer) error {
	var unsafeEntries []string
	for _, e := range reg.Entries {
		if e.Unsafe {
			unsafeEntries = append(unsafeEntries, e.Name)
		}
	}
	names := strings.Join(unsafeEntries, ", ")
	root := findProjectRoot(entryDir)
	enabled, found := false, false
	if root != "" {
		var err error
		enabled, found, err = readLinkUnsafe(root)
		if err != nil {
			return err
		}
	}
	if len(unsafeEntries) == 0 {
		// S8 §7：link.unsafe=true 启用后构建日志必须记录（即使本次没有 @unsafe 入口）。
		if found && enabled {
			fmt.Fprintln(stderr, "xnull: link.unsafe=true（S8 §7）")
		}
		return nil
	}
	if root == "" || !found {
		return fmt.Errorf("@unsafe 受控入口 [%s] 需要工程清单 %s 且 link.unsafe = true（S7 §8 / S8 §7）",
			names, projectManifest)
	}
	if !enabled {
		return fmt.Errorf("@unsafe 受控入口 [%s] 被拒绝：工程清单 link.unsafe 未开启（S8 §7）", names)
	}
	fmt.Fprintf(stderr, "xnull: link.unsafe=true：构建包含 @unsafe 受控入口 [%s]（S7 §8）\n", names)
	return nil
}
