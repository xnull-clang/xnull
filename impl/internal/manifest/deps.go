package manifest

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/xpd"
)

// 精确版本：X.Y.Z 或 X.Y.Z-<预发布>；范围/SNAPSHOT/LATEST/RELEASE/* 一律拒绝（S8 §4.3）。
var exactVersionRe = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$`)

// ResolveDependencies 在 Load 之上完成版本仲裁（S8 §3.5 / §4.2/§4.3）：
// 依赖自身版本 > 最近的管理版本；都无则失败；显式覆盖管理版本记警告。
func ResolveDependencies(path string, opts Options) (*Resolved, []diag.Diagnostic, error) {
	res, diags, err := Load(path, opts)
	if err != nil || len(diags) > 0 {
		return res, diags, err
	}
	var ds []diag.Diagnostic
	coords := make([]string, 0, len(res.Dependencies))
	for c := range res.Dependencies {
		coords = append(coords, c)
	}
	sort.Strings(coords)
	for _, coord := range coords {
		ver := res.Dependencies[coord]
		if ver == "" {
			if mv, ok := res.Managed[coord]; ok && mv != "" {
				ver = mv
			}
		}
		if ver == "" {
			if mv, ok := opts.ManagedFallback[coord]; ok && mv != "" {
				ver = mv
			}
		}
		if ver == "" {
			ds = append(ds, diag.Diagnostic{File: res.Chain[len(res.Chain)-1], Line: 1, Col: 1,
				Code: codeDepVersion, Message: fmt.Sprintf("依赖 %s 无版本：自身未写且 management 未提供（S8 §3.5）", coord)})
			continue
		}
		if !exactVersionRe.MatchString(ver) || hasBannedVersionForm(ver) {
			ds = append(ds, diag.Diagnostic{File: res.Chain[len(res.Chain)-1], Line: 1, Col: 1,
				Code: codeVersionForm, Message: fmt.Sprintf("依赖 %s 的版本 %q 非法：只接受精确版本（S8 §4.3）", coord, ver)})
			continue
		}
		if own := res.Dependencies[coord]; own != "" {
			if mv, ok := res.Managed[coord]; ok && mv != "" && mv != own {
				res.Warnings = append(res.Warnings,
					fmt.Sprintf("依赖 %s 显式版本 %s 覆盖管理版本 %s（S8 §3.5）", coord, own, mv))
			}
		}
		res.Dependencies[coord] = ver
	}
	if len(ds) > 0 {
		return nil, ds, nil
	}
	return res, nil, nil
}

// LockEntry 是锁文件中的一条记录（S8 §4.4）。
type LockEntry struct {
	Coordinate string
	Version    string
	Kind       string // dependency | plugin
	Repository string
	SHA256     string
}

// Lock 是 xnull.lock 的内存形态。
type Lock struct {
	Version int
	Entries []LockEntry
}

func (l *Lock) entry(coord string) (LockEntry, bool) {
	for _, e := range l.Entries {
		if e.Coordinate == coord {
			return e, true
		}
	}
	return LockEntry{}, false
}

// GenerateLock 依据解析结果生成锁（坐标升序）；摘要优先沿用 prev，其次本地仓库 XNULL_REPO。
func GenerateLock(res *Resolved, repoRoot string, prev *Lock) (*Lock, []diag.Diagnostic) {
	var ds []diag.Diagnostic
	coords := make([]string, 0, len(res.Dependencies))
	for c := range res.Dependencies {
		coords = append(coords, c)
	}
	sort.Strings(coords)
	out := &Lock{Version: 1}
	for _, coord := range coords {
		ver := res.Dependencies[coord]
		sum := ""
		if prev != nil {
			if e, ok := prev.entry(coord); ok && e.Version == ver {
				sum = e.SHA256
			}
		}
		if sum == "" && repoRoot != "" {
			if got, ok := artifactSHA(repoRoot, coord, ver); ok {
				sum = got
			}
		}
		if sum == "" {
			ds = append(ds, diag.Diagnostic{File: "xnull.lock", Line: 1, Col: 1, Code: codeLockMismatch,
				Message: fmt.Sprintf("无法取得 %s %s 的制品摘要：请设置 XNULL_REPO 指向本地仓库（S8 §4.4）", coord, ver)})
			continue
		}
		out.Entries = append(out.Entries, LockEntry{Coordinate: coord, Version: ver, Kind: "dependency",
			Repository: "central", SHA256: sum})
	}
	if len(ds) > 0 {
		return nil, ds
	}
	return out, nil
}

// artifactSHA 在本地仓库 group/artifact/version/ 下找 <artifact>-<version>.<ext> 并计算 sha256。
func artifactSHA(repoRoot, coord, version string) (string, bool) {
	parts := strings.SplitN(coord, ":", 2)
	if len(parts) != 2 {
		return "", false
	}
	dir := filepath.Join(repoRoot, filepath.FromSlash(strings.ReplaceAll(parts[0], ".", "/")), parts[1], version)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return "", false
	}
	prefix := parts[1] + "-" + version + "."
	for _, e := range entries {
		if e.IsDir() || !strings.HasPrefix(e.Name(), prefix) {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			return "", false
		}
		sum := sha256.Sum256(data)
		return hex.EncodeToString(sum[:]), true
	}
	return "", false
}

// LoadLock 读取并做形态校验（版本号/摘要格式/坐标排序/一条一坐标）。
func LoadLock(path string) (*Lock, []diag.Diagnostic, error) {
	src, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, err
	}
	f, sdiags := xpd.Parse(path, string(src))
	if len(sdiags) > 0 {
		return nil, sdiags, nil
	}
	root := f.Find("lock")
	if root == nil {
		return nil, []diag.Diagnostic{{File: path, Line: 1, Col: 1, Code: codeLockMismatch, Message: "锁文件缺少 lock 块（S8 §4.4）"}}, nil
	}
	lock := &Lock{Version: 1}
	var ds []diag.Diagnostic
	seen := map[string]bool{}
	prev := ""
	for _, n := range root.Children {
		switch node := n.(type) {
		case *xpd.Field:
			if node.Name == "version" {
				var v int
				fmt.Sscanf(node.Value.Text, "%d", &v)
				if v != 1 {
					ds = append(ds, diag.Diagnostic{File: path, Line: node.Pos.Line, Col: node.Pos.Col,
						Code: codeLockMismatch, Message: fmt.Sprintf("锁版本只支持 1，实际 %q（S8 §4.4）", node.Value.Text)})
				}
			}
		case *xpd.Block:
			if node.Name != "entry" || len(node.Args) < 2 {
				continue
			}
			e := LockEntry{Coordinate: node.Args[0].Text, Version: node.Args[1].Text}
			for _, c := range node.Children {
				fld, ok := c.(*xpd.Field)
				if !ok {
					continue
				}
				switch fld.Name {
				case "kind":
					e.Kind = fld.Value.Text
				case "repository":
					e.Repository = fld.Value.Text
				case "sha256":
					e.SHA256 = fld.Value.Text
				}
			}
			if seen[e.Coordinate] {
				ds = append(ds, diag.Diagnostic{File: path, Line: node.Pos.Line, Col: node.Pos.Col,
					Code: codeLockExtra, Message: fmt.Sprintf("锁内坐标重复：%s（S8 §4.4）", e.Coordinate)})
			}
			seen[e.Coordinate] = true
			if prev != "" && e.Coordinate < prev {
				ds = append(ds, diag.Diagnostic{File: path, Line: node.Pos.Line, Col: node.Pos.Col,
					Code: codeLockDigest, Message: fmt.Sprintf("锁条目未按坐标升序：%s 在 %s 之后（S8 §4.4）", e.Coordinate, prev)})
			}
			prev = e.Coordinate
			if !isHex64(e.SHA256) {
				ds = append(ds, diag.Diagnostic{File: path, Line: node.Pos.Line, Col: node.Pos.Col,
					Code: codeLockDigest, Message: fmt.Sprintf("sha256 必须是 64 位小写十六进制：%s", e.Coordinate)})
			}
			lock.Entries = append(lock.Entries, e)
		}
	}
	if len(ds) > 0 {
		return nil, ds, nil
	}
	return lock, nil, nil
}

// hasBannedVersionForm 拒绝 SNAPSHOT / LATEST / RELEASE / * 与范围符号（S8 §4.3）。
func hasBannedVersionForm(v string) bool {
	up := strings.ToUpper(v)
	if strings.Contains(up, "SNAPSHOT") || strings.Contains(up, "LATEST") || strings.Contains(up, "RELEASE") {
		return true
	}
	for _, ch := range []string{"*", "[", "]", "(", ")", ","} {
		if strings.Contains(v, ch) {
			return true
		}
	}
	return false
}

func isHex64(s string) bool {
	if len(s) != 64 {
		return false
	}
	for _, r := range s {
		if !(r >= '0' && r <= '9') && !(r >= 'a' && r <= 'f') {
			return false
		}
	}
	return true
}

// ValidateLock 校验锁与清单一致（S8 §4.4）：缺条目/版本不一致 → 404，
// 多余坐标 → 405，摘要格式或内容不符 → 406。
func ValidateLock(lock *Lock, res *Resolved, repoRoot string) []diag.Diagnostic {
	var ds []diag.Diagnostic
	file := "xnull.lock"
	manifestCoords := map[string]bool{}
	for coord, ver := range res.Dependencies {
		manifestCoords[coord] = true
		e, ok := lock.entry(coord)
		if !ok {
			ds = append(ds, diag.Diagnostic{File: file, Line: 1, Col: 1, Code: codeLockMismatch,
				Message: fmt.Sprintf("锁缺少依赖 %s %s（清单已变更，请 --update-lock，S8 §4.4）", coord, ver)})
			continue
		}
		if e.Version != ver || e.Kind != "dependency" {
			ds = append(ds, diag.Diagnostic{File: file, Line: 1, Col: 1, Code: codeLockMismatch,
				Message: fmt.Sprintf("锁与清单不一致：%s 锁 %s/%s，清单 %s/dependency（S8 §4.4）", coord, e.Version, e.Kind, ver)})
			continue
		}
		if !isHex64(e.SHA256) {
			ds = append(ds, diag.Diagnostic{File: file, Line: 1, Col: 1, Code: codeLockDigest,
				Message: fmt.Sprintf("锁摘要格式非法：%s", coord)})
			continue
		}
		if repoRoot != "" {
			if got, ok := artifactSHA(repoRoot, coord, ver); ok && got != e.SHA256 {
				ds = append(ds, diag.Diagnostic{File: file, Line: 1, Col: 1, Code: codeLockDigest,
					Message: fmt.Sprintf("制品摘要不符：%s %s（S8 §4.4）", coord, ver)})
			}
		}
	}
	for _, e := range lock.Entries {
		if !manifestCoords[e.Coordinate] {
			ds = append(ds, diag.Diagnostic{File: file, Line: 1, Col: 1, Code: codeLockExtra,
				Message: fmt.Sprintf("锁中坐标在清单中不存在：%s（S8 §4.4）", e.Coordinate)})
		}
	}
	return ds
}

// WriteLock 以稳定字节格式写锁（坐标升序，字段对齐同规范样例）。
func WriteLock(path string, l *Lock) error {
	entries := append([]LockEntry{}, l.Entries...)
	sort.Slice(entries, func(i, j int) bool { return entries[i].Coordinate < entries[j].Coordinate })
	var b strings.Builder
	b.WriteString("lock {\n")
	fmt.Fprintf(&b, "  version = %d\n", l.Version)
	for _, e := range entries {
		fmt.Fprintf(&b, "\n  entry %s %s {\n", e.Coordinate, e.Version)
		fmt.Fprintf(&b, "    kind       = %s\n", e.Kind)
		fmt.Fprintf(&b, "    repository = %s\n", e.Repository)
		fmt.Fprintf(&b, "    sha256     = %s\n", e.SHA256)
		b.WriteString("  }\n")
	}
	b.WriteString("}\n")
	return os.WriteFile(path, []byte(b.String()), 0o644)
}
