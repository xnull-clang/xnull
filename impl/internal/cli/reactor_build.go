// reactor_build.go：S8-14 聚合工程构建入口（pom + modules 拓扑构建、失败即停、聚合摘要）。
package cli

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"xnull.dev/xnull/internal/exitcode"
	"xnull.dev/xnull/internal/reactor"
)

// runReactorBuild 构建聚合根下所有模块（拓扑序），并写聚合摘要。
func runReactorBuild(env Env, rest []string, root, profile string) (string, int) {
	plan, ds, err := reactor.Load(root, reactor.Options{
		ToolchainVersion: Version,
		Platform:         platformName(),
		Profiles:         profileList(profile),
	})
	if err != nil {
		fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
		return "", exitcode.BuildFail
	}
	if len(ds) > 0 {
		printDiags(env, ds)
		return "", exitcode.BuildFail
	}
	results, bds := reactor.Build(plan, func(m reactor.Module) (string, error) {
		artifact, code := buildManifestManaged(env, rest, m.Dir, plan.Managed)
		if code != exitcode.Success {
			return "", fmt.Errorf("模块 %s 构建失败（exit=%d）", m.Rel, code)
		}
		return artifact, nil
	})
	if len(bds) > 0 {
		printDiags(env, bds)
		return "", exitcode.BuildFail
	}

	// 聚合摘要：模块顺序 + 产物 + sha256，写聚合根 target/。
	lines := make([]string, 0, len(results))
	for _, r := range results {
		sum := ""
		if data, rerr := os.ReadFile(r.Artifact); rerr == nil {
			h := sha256.Sum256(data)
			sum = hex.EncodeToString(h[:])
		}
		lines = append(lines, fmt.Sprintf("module %s %s %s", r.Module, r.Artifact, sum))
	}
	// 已按拓扑序输出，不再排序；仅对相同模块保证稳定。
	summaryPath := filepath.Join(root, "target", "reactor-summary.txt")
	if err := os.MkdirAll(filepath.Dir(summaryPath), 0o755); err != nil {
		fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
		return "", exitcode.BuildFail
	}
	body := "# reactor 聚合摘要（脚本生成，手改即作废）\n" + strings.Join(lines, "\n") + "\n"
	if err := os.WriteFile(summaryPath, []byte(body), 0o644); err != nil {
		fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
		return "", exitcode.BuildFail
	}
	for _, line := range lines {
		fmt.Fprintln(env.Stdout, line)
	}
	return summaryPath, exitcode.Success
}
