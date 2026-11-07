// Package repro 实现 S8 §8 可复现性：输入穷举、摘要、锁字节稳定与 target 外写检测。
// `.xmeta` 字段渲染归 E4 的 S8-04；本包只提供摘要与比对原语。
package repro

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/manifest"
)

// LockEntry 是锁条目（与 manifest 同构，便于测试与调用方直用）。
type LockEntry = manifest.LockEntry

// WriteLockStable 以稳定字节格式写锁：坐标升序，字段固定对齐；与输入顺序无关。
func WriteLockStable(path string, entries []LockEntry) error {
	sorted := append([]LockEntry{}, entries...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Coordinate < sorted[j].Coordinate })
	var b strings.Builder
	b.WriteString("lock {\n  version = 1\n")
	for _, e := range sorted {
		fmt.Fprintf(&b, "\n  entry %s %s {\n", e.Coordinate, e.Version)
		fmt.Fprintf(&b, "    kind       = %s\n", e.Kind)
		fmt.Fprintf(&b, "    repository = %s\n", e.Repository)
		fmt.Fprintf(&b, "    sha256     = %s\n", e.SHA256)
		b.WriteString("  }\n")
	}
	b.WriteString("}\n")
	return os.WriteFile(path, []byte(b.String()), 0o644)
}

// InputSpec 是输入穷举的声明（S8 §8）。
type InputSpec struct {
	ProjectDir  string
	Manifests   []string // 清单链（相对路径）
	SourceRoots []string // 源码根（相对路径）
	LockPath    string   // 锁文件（相对路径；缺失记 absent）
	Toolchain   string
	Platform    string
	Profiles    []string
}

// Inputs 是采集后的输入清单与摘要。
type Inputs struct {
	Canonical string
	DigestHex string
	Files     []FileHash
}

// FileHash 是单个输入文件的摘要。
type FileHash struct {
	Path   string
	SHA256 string
}

// CollectInputs 采集输入并生成稳定摘要（集合一律排序）。
func CollectInputs(spec InputSpec) (*Inputs, error) {
	var files []FileHash
	for _, rel := range spec.Manifests {
		fh, err := hashFile(spec.ProjectDir, rel)
		if err != nil {
			return nil, err
		}
		files = append(files, fh)
	}
	for _, root := range spec.SourceRoots {
		hs, err := hashTree(spec.ProjectDir, root)
		if err != nil {
			return nil, err
		}
		files = append(files, hs...)
	}
	if spec.LockPath != "" {
		if fh, err := hashFile(spec.ProjectDir, spec.LockPath); err == nil {
			files = append(files, fh)
		} else {
			files = append(files, FileHash{Path: spec.LockPath, SHA256: "absent"})
		}
	}
	sort.Slice(files, func(i, j int) bool { return files[i].Path < files[j].Path })

	profiles := append([]string{}, spec.Profiles...)
	sort.Strings(profiles)

	var b strings.Builder
	fmt.Fprintf(&b, "toolchain\t%s\n", spec.Toolchain)
	fmt.Fprintf(&b, "platform\t%s\n", spec.Platform)
	fmt.Fprintf(&b, "profiles\t%s\n", strings.Join(profiles, ","))
	for _, f := range files {
		fmt.Fprintf(&b, "file\t%s\t%s\n", f.Path, f.SHA256)
	}
	canonical := b.String()
	sum := sha256.Sum256([]byte(canonical))
	return &Inputs{Canonical: canonical, DigestHex: hex.EncodeToString(sum[:]), Files: files}, nil
}

// Digest 返回输入摘要。
func (in *Inputs) Digest() string { return in.DigestHex }

// BuildSummary 是一次构建的可复现摘要（两次构建比对用）。
type BuildSummary struct {
	Inputs      string
	InputDigest string
}

// Summary 采集一次构建摘要。
func Summary(spec InputSpec) (BuildSummary, error) {
	in, err := CollectInputs(spec)
	if err != nil {
		return BuildSummary{}, err
	}
	return BuildSummary{Inputs: in.Canonical, InputDigest: in.DigestHex}, nil
}

// SameSummary 比较两次构建摘要是否一致。
func SameSummary(a, b BuildSummary) bool {
	return a.InputDigest != "" && a.InputDigest == b.InputDigest
}

func hashFile(root, rel string) (FileHash, error) {
	data, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rel)))
	if err != nil {
		return FileHash{}, err
	}
	sum := sha256.Sum256(data)
	return FileHash{Path: filepath.ToSlash(rel), SHA256: hex.EncodeToString(sum[:])}, nil
}

func hashTree(root, relRoot string) ([]FileHash, error) {
	base := filepath.Join(root, filepath.FromSlash(relRoot))
	var out []FileHash
	err := filepath.WalkDir(base, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		data, rerr := os.ReadFile(path)
		if rerr != nil {
			return rerr
		}
		rel, rerr := filepath.Rel(root, path)
		if rerr != nil {
			return rerr
		}
		sum := sha256.Sum256(data)
		out = append(out, FileHash{Path: filepath.ToSlash(rel), SHA256: hex.EncodeToString(sum[:])})
		return nil
	})
	return out, err
}

// Snapshot 记录 excludeDirs 之外的文件摘要（用于 target 外写检测）。
func Snapshot(root string, excludeDirs []string) (map[string]string, error) {
	excl := map[string]bool{}
	for _, d := range excludeDirs {
		excl[filepath.ToSlash(filepath.Clean(d))] = true
	}
	out := map[string]string{}
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, rerr := filepath.Rel(root, path)
		if rerr != nil {
			return rerr
		}
		rel = filepath.ToSlash(rel)
		if d.IsDir() {
			if d.Name() == ".git" || excl[rel] {
				return filepath.SkipDir
			}
			return nil
		}
		data, rerr := os.ReadFile(path)
		if rerr != nil {
			return nil
		}
		sum := sha256.Sum256(data)
		out[rel] = hex.EncodeToString(sum[:])
		return nil
	})
	return out, err
}

// CheckWrites 比较两个快照：target 之外的新增/修改/删除均报 REPRO-001。
func CheckWrites(before, after map[string]string, root string) []diag.Diagnostic {
	var ds []diag.Diagnostic
	var rels []string
	for p := range after {
		rels = append(rels, p)
	}
	sort.Strings(rels)
	for _, p := range rels {
		if old, ok := before[p]; !ok {
			ds = append(ds, diag.Diagnostic{File: filepath.Join(root, p), Line: 1, Col: 1,
				Code: "REPRO-001", Message: fmt.Sprintf("target/ 之外新增文件：%s（S8 §8/PROJ-09）", p)})
		} else if old != after[p] {
			ds = append(ds, diag.Diagnostic{File: filepath.Join(root, p), Line: 1, Col: 1,
				Code: "REPRO-001", Message: fmt.Sprintf("target/ 之外文件被修改：%s（S8 §8/PROJ-09）", p)})
		}
	}
	rels = rels[:0]
	for p := range before {
		rels = append(rels, p)
	}
	sort.Strings(rels)
	for _, p := range rels {
		if _, ok := after[p]; !ok {
			ds = append(ds, diag.Diagnostic{File: filepath.Join(root, p), Line: 1, Col: 1,
				Code: "REPRO-001", Message: fmt.Sprintf("target/ 之外文件被删除：%s（S8 §8/PROJ-09）", p)})
		}
	}
	return ds
}
