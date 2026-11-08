// manifest_integration.go：S8 集成收口——validate 阶段接入锁/配置/资源/插件。
package cli

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/config"
	"xnull.dev/xnull/internal/devtool"
	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/manifest"
	"xnull.dev/xnull/internal/plugin"
	"xnull.dev/xnull/internal/resman"
)

type integrationState struct {
	resC         string
	cfgDigest    string
	resDigest    string
	pluginDigest string
	profiles     []string
	plugins      []string
}

func platformName() string {
	if runtime.GOOS == "darwin" {
		return "macos"
	}
	return runtime.GOOS
}

func printDiags(env Env, ds []diag.Diagnostic) {
	for _, d := range ds {
		fmt.Fprintln(env.Stderr, d.String())
	}
}

// validateIntegrations 依次执行：锁校验（存在则校验）→ config.Load → resman.Collect → 插件校验。
// 任一失败即停（失败即停，不继续后续阶段）。
func (p *manifestPipeline) validateIntegrations(profile string) (*integrationState, bool) {
	st := &integrationState{}
	res, ds, err := manifest.ResolveDependencies(p.m.Path, manifest.Options{
		ToolchainVersion: Version,
		Profiles:         profileList(profile),
		Platform:         platformName(),
	})
	if err != nil {
		fmt.Fprintf(p.env.Stderr, "xnull: %v\n", err)
		return nil, false
	}
	if len(ds) > 0 {
		printDiags(p.env, ds)
		return nil, false
	}
	st.profiles = append([]string{}, res.ActiveProfiles...)
	repo := os.Getenv("XNULL_REPO")

	// 1) 锁：存在则校验（缺锁不阻断；首次构建由 lock --update-lock 生成）。
	lockPath := filepath.Join(p.m.Root, "xnull.lock")
	if _, statErr := os.Stat(lockPath); statErr == nil {
		lock, lds, lerr := manifest.LoadLock(lockPath)
		if lerr != nil {
			fmt.Fprintf(p.env.Stderr, "xnull: 读锁失败：%v\n", lerr)
			return nil, false
		}
		if len(lds) > 0 {
			printDiags(p.env, lds)
			return nil, false
		}
		graph, gds := manifest.ResolveGraph(res, repo)
		if len(gds) > 0 {
			printDiags(p.env, gds)
			return nil, false
		}
		if vds := manifest.ValidateLockForGraph(lock, graph, repo); len(vds) > 0 {
			printDiags(p.env, vds)
			return nil, false
		}
	}

	// 2) 配置：五层覆盖 + profile/环境白名单（XPD-6xx）。
	resourcesDir := filepath.Join(p.m.Root, "src", "main", "resources")
	specKeys := map[string]config.KeySpec{}
	for k := range res.Configuration {
		specKeys[k] = config.KeySpec{Kind: config.KindString}
	}
	cfg, cds := config.Load(config.Options{
		ResourcesDir:  resourcesDir,
		Profile:       profile,
		Packaging:     p.m.Packaging,
		Configuration: res.Configuration,
		Spec:          config.Spec{Keys: specKeys, Profiles: res.ActiveProfiles},
	})
	if len(cds) > 0 {
		printDiags(p.env, cds)
		return nil, false
	}
	st.cfgDigest = hashKeyValues(cfg.Values)

	// 3) 资源：资源根/glob/冲突（XPD-8xx）。
	roots := make([]resman.Root, 0, len(res.ResourceRoots))
	owner := p.m.GroupID + ":" + p.m.ArtifactID
	for _, rr := range res.ResourceRoots {
		roots = append(roots, resman.Root{
			Path:     filepath.Join(p.m.Root, filepath.FromSlash(rr.Dir)),
			Includes: rr.Includes,
			Excludes: rr.Excludes,
			Owner:    owner,
		})
	}
	if len(roots) == 0 {
		if st, err := os.Stat(resourcesDir); err == nil && st.IsDir() {
			roots = append(roots, resman.Root{Path: resourcesDir, Owner: owner})
		}
	}
	set, rds := resman.CollectForPackaging(p.m.Packaging, roots)
	if len(rds) > 0 {
		printDiags(p.env, rds)
		return nil, false
	}
	tableEntries := map[string][]byte{}
	var resLines []string
	for artifactPath, e := range set.Entries {
		name := strings.TrimPrefix(artifactPath, "resources/")
		tableEntries[name] = e.Data
		resLines = append(resLines, artifactPath+"\x00"+sha256Hex(e.Data))
	}
	sort.Strings(resLines)
	st.resDigest = sha256Hex([]byte(strings.Join(resLines, "\n")))
	resC := filepath.Join(p.m.Root, "target", ".cache", "resources.c")
	if err := os.MkdirAll(filepath.Dir(resC), 0o755); err != nil {
		fmt.Fprintf(p.env.Stderr, "xnull: %v\n", err)
		return nil, false
	}
	if err := devtool.GenerateResourcesFromMap(tableEntries, resC); err != nil {
		fmt.Fprintf(p.env.Stderr, "xnull: 生成资源表失败：%v\n", err)
		return nil, false
	}
	st.resC = resC

	// 4) 插件：.xplugin 元数据与声明一致性（XPD-5xx）。
	var pluginLines []string
	for _, decl := range res.Plugins {
		metaPath := pluginMetaPath(p.m.Root, repo, decl.Coordinate, decl.Version)
		md, mds, merr := plugin.LoadMetadata(metaPath)
		if merr != nil {
			fmt.Fprintf(p.env.Stderr, "xnull: %v\n", merr)
			return nil, false
		}
		if len(mds) > 0 {
			printDiags(p.env, mds)
			return nil, false
		}
		vds := plugin.Validate(md, plugin.Decl{
			Coordinate: decl.Coordinate, Version: decl.Version,
			Phase: decl.Phase, Goal: decl.Goal, Config: decl.Config,
		}, Version)
		if len(vds) > 0 {
			printDiags(p.env, vds)
			return nil, false
		}
		label := decl.Coordinate + "@" + decl.Version + ":" + decl.Goal
		st.plugins = append(st.plugins, label)
		pluginLines = append(pluginLines, label)
	}
	sort.Strings(pluginLines)
	st.pluginDigest = sha256Hex([]byte(strings.Join(pluginLines, "\n")))
	return st, true
}

func pluginMetaPath(root, repo, coord, version string) string {
	parts := strings.SplitN(coord, ":", 2)
	if len(parts) != 2 {
		return filepath.Join(root, "plugins", coord, ".xplugin")
	}
	if repo != "" {
		return filepath.Join(repo, filepath.FromSlash(strings.ReplaceAll(parts[0], ".", "/")), parts[1], version, ".xplugin")
	}
	return filepath.Join(root, "plugins", parts[1], ".xplugin")
}

func profileList(profile string) []string {
	if profile == "" {
		return nil
	}
	return []string{profile}
}

func hashKeyValues(values map[string]string) string {
	keys := make([]string, 0, len(values))
	for k := range values {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		b.WriteString(k)
		b.WriteByte('=')
		b.WriteString(values[k])
		b.WriteByte('\n')
	}
	sum := sha256.Sum256([]byte(b.String()))
	return hex.EncodeToString(sum[:])
}
