// Package artifact 实现 S8 §2/§4/§5 的 library 产物与本地仓库：
// `.xlib` 打包（源码 + 清单 + 锁 + 元数据 + 逐文件哈希）、本地仓库安装布局与仓库路径。
// 远程仓库只保留接口（不实现，S8 远程拉取另卡）。
package artifact

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/diag"
)

// Dependency 是写进 .xlib 元数据的依赖项。
type Dependency struct {
	Coordinate string
	Version    string
}

// Spec 是一次 `.xlib` 打包请求。
type Spec struct {
	Root         string
	GroupID      string
	ArtifactID   string
	Version      string
	Packaging    string
	ManifestPath string
	SourceRoot   string   // 相对工程根，如 src/main/x
	ResourceDirs []string // 相对工程根
	LockPath     string   // 可选
	Dependencies []Dependency
}

// Info 是产物信息。
type Info struct {
	Path   string
	SHA256 string
	Files  int
}

// RepoDir 返回本地仓库中某坐标的目录：<repo>/<group 点转斜杠>/<artifact>/<version>。
func RepoDir(repoRoot, groupID, artifactID, version string) string {
	return filepath.Join(repoRoot, filepath.FromSlash(strings.ReplaceAll(groupID, ".", "/")), artifactID, version)
}

// XlibName 返回制品文件名 `<artifactId>-<version>.xlib`。
func XlibName(artifactID, version string) string {
	return artifactID + "-" + version + ".xlib"
}

// Build 生成确定性 `.xlib`：条目按名称排序、Store 压缩、零时间戳；返回 sha256。
func Build(spec Spec, outPath string) (Info, []diag.Diagnostic, error) {
	files := map[string][]byte{}
	manifestData, err := os.ReadFile(spec.ManifestPath)
	if err != nil {
		return Info{}, nil, err
	}
	files["xnull.project"] = manifestData
	if spec.LockPath != "" {
		if lockData, lerr := os.ReadFile(spec.LockPath); lerr == nil {
			files["xnull.lock"] = lockData
		}
	}
	collect := func(dir string) error {
		abs := filepath.Join(spec.Root, filepath.FromSlash(dir))
		st, serr := os.Stat(abs)
		if serr != nil || !st.IsDir() {
			return nil
		}
		return filepath.WalkDir(abs, func(path string, d os.DirEntry, werr error) error {
			if werr != nil || d.IsDir() {
				return werr
			}
			rel, rerr := filepath.Rel(spec.Root, path)
			if rerr != nil {
				return rerr
			}
			data, rerr := os.ReadFile(path)
			if rerr != nil {
				return rerr
			}
			files[filepath.ToSlash(rel)] = data
			return nil
		})
	}
	if err := collect(spec.SourceRoot); err != nil {
		return Info{}, nil, err
	}
	for _, dir := range spec.ResourceDirs {
		if err := collect(dir); err != nil {
			return Info{}, nil, err
		}
	}

	names := make([]string, 0, len(files))
	for name := range files {
		names = append(names, name)
	}
	sort.Strings(names)
	var meta strings.Builder
	meta.WriteString("xlib {\n")
	fmt.Fprintf(&meta, "  groupId    = %s\n", spec.GroupID)
	fmt.Fprintf(&meta, "  artifactId = %s\n", spec.ArtifactID)
	fmt.Fprintf(&meta, "  version    = %s\n", spec.Version)
	fmt.Fprintf(&meta, "  packaging  = %s\n", spec.Packaging)
	deps := append([]Dependency{}, spec.Dependencies...)
	sort.Slice(deps, func(i, j int) bool { return deps[i].Coordinate < deps[j].Coordinate })
	for _, d := range deps {
		fmt.Fprintf(&meta, "  dependency %s %s\n", d.Coordinate, d.Version)
	}
	meta.WriteString("  files {\n")
	for _, name := range names {
		sum := sha256.Sum256(files[name])
		fmt.Fprintf(&meta, "    %s %s\n", hex.EncodeToString(sum[:]), name)
	}
	meta.WriteString("  }\n}\n")

	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	all := append([]string{"xlib.meta"}, names...)
	sort.Strings(all)
	for _, name := range all {
		hdr := &zip.FileHeader{Name: name, Method: zip.Store}
		hdr.SetMode(0o644)
		w, werr := zw.CreateHeader(hdr)
		if werr != nil {
			return Info{}, nil, werr
		}
		data := files[name]
		if name == "xlib.meta" {
			data = []byte(meta.String())
		}
		if _, werr := w.Write(data); werr != nil {
			return Info{}, nil, werr
		}
	}
	if err := zw.Close(); err != nil {
		return Info{}, nil, err
	}
	if err := os.MkdirAll(filepath.Dir(outPath), 0o755); err != nil {
		return Info{}, nil, err
	}
	if err := os.WriteFile(outPath, buf.Bytes(), 0o644); err != nil {
		return Info{}, nil, err
	}
	sum := sha256.Sum256(buf.Bytes())
	return Info{Path: outPath, SHA256: hex.EncodeToString(sum[:]), Files: len(names)}, nil, nil
}

// Install 把 `.xlib` 与清单复制到本地仓库（S8 §4 布局）。
func Install(repoRoot string, spec Spec, xlibPath string) (string, error) {
	dir := RepoDir(repoRoot, spec.GroupID, spec.ArtifactID, spec.Version)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	dst := filepath.Join(dir, XlibName(spec.ArtifactID, spec.Version))
	data, err := os.ReadFile(xlibPath)
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(dst, data, 0o644); err != nil {
		return "", err
	}
	manifestData, err := os.ReadFile(spec.ManifestPath)
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(filepath.Join(dir, "xnull.project"), manifestData, 0o644); err != nil {
		return "", err
	}
	return dst, nil
}

// Remote 是远程仓库接口（1.x 不实现；调用返回明确错误，不静默降级）。
type Remote interface {
	// Fetch 拉取坐标制品；未实现时返回错误。
	Fetch(groupID, artifactID, version string) ([]byte, error)
}

// ErrRemoteUnimplemented 表示远程仓库拉取尚未实现。
var ErrRemoteUnimplemented = fmt.Errorf("远程仓库拉取未实现（S8 §4.7；1.x 只用本地仓库）")
