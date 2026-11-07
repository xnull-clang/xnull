package devtool

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// RepoRoot 从 start 向上定位仓库根（与 dev check 同一布局口径）。
func RepoRoot(start string) (string, error) {
	l, err := findLayout(start)
	if err != nil {
		return "", err
	}
	return l.Root, nil
}

// BoardOptions 是 SSOT 看板生成参数。
type BoardOptions struct {
	Since    time.Duration // 统计窗口，缺省 7 天
	RunTests bool          // 是否现场跑 go test ./...
	Now      time.Time     // 注入时间（测试用）
}

type commitInfo struct {
	sha, author, subject string
	when                 time.Time
	files                []string
}

type evidenceInfo struct {
	name  string
	files int
	mtime time.Time
}

type testSummary struct {
	ran      bool
	green    bool
	okPkgs   int
	failPkgs []string
}

// GenerateBoard 从 git log + go test + 台账 status.tsv + evidence/ 生成 SSOT 看板。
// 输出即唯一看板；任何手改副本作废（ADR-001 §4）。
func GenerateBoard(root, implDir string, opts BoardOptions, out io.Writer) error {
	if opts.Since <= 0 {
		opts.Since = 7 * 24 * time.Hour
	}
	if opts.Now.IsZero() {
		opts.Now = time.Now()
	}
	sinceISO := opts.Now.Add(-opts.Since).Format("2006-01-02T15:04:05")

	branch, err := gitLine(root, "rev-parse", "--abbrev-ref", "HEAD")
	if err != nil {
		return fmt.Errorf("不是 git 仓库或无法读取 HEAD：%v", err)
	}
	head, err := gitLine(root, "rev-parse", "--short", "HEAD")
	if err != nil {
		return fmt.Errorf("无法读取 HEAD：%v", err)
	}
	commits, err := loadCommits(root, sinceISO)
	if err != nil {
		return err
	}

	statusPath := filepath.Join(root, "impl", "docs", "conformance", "status.tsv")
	status, err := loadStatus(statusPath)
	if err != nil {
		return err
	}
	counts := map[string]int{}
	for _, s := range status {
		counts[s.state]++
	}
	passNow := counts["PASS"]
	passBase := passNow
	windowStart := ""
	if len(commits) > 0 {
		first := commits[len(commits)-1].sha
		windowStart = first
		if data, err := gitShow(root, first, "impl/docs/conformance/status.tsv"); err == nil {
			passBase = countPass(data)
		}
	}

	var tests testSummary
	if opts.RunTests {
		tests = runTests(implDir)
	}

	evidence, err := loadEvidence(filepath.Join(root, "evidence"))
	if err != nil {
		return err
	}
	gates := gateProgress(evidence, root)

	var b strings.Builder
	fmt.Fprintf(&b, "# SSOT 看板（脚本生成，手改即作废）\n\n")
	fmt.Fprintf(&b, "- 生成时间：%s\n", opts.Now.Format("2006-01-02 15:04:05 -0700"))
	fmt.Fprintf(&b, "- 仓库：`%s`　分支：`%s`　HEAD：`%s`\n", filepath.Base(root), branch, head)
	fmt.Fprintf(&b, "- 窗口：近 %s（起点提交 `%s`）\n", humanDuration(opts.Since), windowStart)
	fmt.Fprintf(&b, "- 数据源：git log / go test / impl/docs/conformance/status.tsv / evidence/\n\n")

	// 四数（ADR-001 §7）
	fmt.Fprintf(&b, "## 四数\n\n")
	fmt.Fprintf(&b, "| # | 指标 | 值 |\n|---|---|---|\n")
	fmt.Fprintf(&b, "| 1 | 窗口内 commit 数 | %d |\n", len(commits))
	delta := passNow - passBase
	sign := "+"
	if delta < 0 {
		sign = ""
	}
	fmt.Fprintf(&b, "| 2 | 锚点翻转（PASS） | %d（起点 %d，Δ%s%d） |\n", passNow, passBase, sign, delta)
	fmt.Fprintf(&b, "| 3 | 全量测试 | %s |\n", testCell(tests))
	fmt.Fprintf(&b, "| 4 | 门进度 | %s |\n\n", gateCell(gates))

	// 台账分布
	fmt.Fprintf(&b, "## 台账锚点（status.tsv 已登记 %d 行）\n\n", len(status))
	fmt.Fprintf(&b, "| 状态 | 数量 |\n|---|---|\n")
	for _, st := range []string{"PASS", "部分", "未实现", "N/A"} {
		fmt.Fprintf(&b, "| %s | %d |\n", st, counts[st])
	}
	fmt.Fprintf(&b, "\n> 未登记锚点在台账中显示「未实现」（口径见 impl/docs/conformance/ledger-restructure.md）。\n\n")

	// 生产线（3 生产 + 2 支撑）
	fmt.Fprintf(&b, "## 生产线进度（窗口内 commit / 最近一条）\n\n")
	fmt.Fprintf(&b, "| 线 | Owner | commit | 最近提交 |\n|---|---|---|---|\n")
	for _, ln := range boardLines {
		n := 0
		latest := "—"
		for i := len(commits) - 1; i >= 0; i-- {
			if lineOf(commits[i].files) == ln.name {
				n++
				latest = commits[i].sha + " " + truncateRunes(commits[i].subject, 40)
			}
		}
		fmt.Fprintf(&b, "| %s | %s | %d | %s |\n", ln.name, ln.owner, n, latest)
	}
	fmt.Fprintf(&b, "\n")

	// 最近提交
	fmt.Fprintf(&b, "## 最近提交（最多 15 条）\n\n")
	fmt.Fprintf(&b, "| sha | 日期 | 作者 | 主题 |\n|---|---|---|---|\n")
	limit := len(commits)
	if limit > 15 {
		limit = 15
	}
	for i := 0; i < limit; i++ {
		c := commits[i]
		fmt.Fprintf(&b, "| %s | %s | %s | %s |\n", c.sha, c.when.Format("01-02 15:04"), c.author, truncateRunes(c.subject, 60))
	}
	fmt.Fprintf(&b, "\n")

	// evidence
	fmt.Fprintf(&b, "## evidence（按最近修改，最多 10 项；共 %d 项）\n\n", len(evidence))
	fmt.Fprintf(&b, "| 目录 | 文件数 | 最近修改 |\n|---|---|---|\n")
	limit = len(evidence)
	if limit > 10 {
		limit = 10
	}
	for i := 0; i < limit; i++ {
		e := evidence[i]
		fmt.Fprintf(&b, "| %s | %d | %s |\n", e.name, e.files, e.mtime.Format("01-02 15:04"))
	}
	fmt.Fprintf(&b, "\n---\n本文件由 `xnull dev board` 生成；手工编辑无效。\n")

	_, err = io.WriteString(out, b.String())
	return err
}

func humanDuration(d time.Duration) string {
	if d%(24*time.Hour) == 0 {
		return fmt.Sprintf("%d 天", int(d/(24*time.Hour)))
	}
	return d.String()
}

func testCell(t testSummary) string {
	if !t.ran {
		return "未运行（--no-test）"
	}
	if t.green {
		return fmt.Sprintf("绿（%d 包 ok）", t.okPkgs)
	}
	return fmt.Sprintf("红（%d 包失败：%s）", len(t.failPkgs), strings.Join(t.failPkgs, ", "))
}

func gateCell(gates []string) string {
	if len(gates) == 0 {
		return "无门证据"
	}
	return strings.Join(gates, "；")
}

type boardLine struct {
	name  string
	owner string
}

// 3 条生产线 + 2 条支撑线（ADR-002）。
var boardLines = []boardLine{
	{"前端线", "E2"},
	{"自举线", "E4"},
	{"运行时线", "E5"},
	{"QA 线", "QA1"},
	{"发布线", "COO"},
}

// lineOf 按改动路径把提交归到线（支撑线只看 evidence/收件箱）。
func lineOf(files []string) string {
	for _, f := range files {
		switch {
		case strings.HasPrefix(f, "impl/internal/xfront/"), strings.HasPrefix(f, "impl/internal/sema/"):
			return "前端线"
		case strings.HasPrefix(f, "impl/internal/codegen/"), strings.HasPrefix(f, "impl/internal/xnfmt/"),
			strings.HasPrefix(f, "impl/cmd/"):
			return "自举线"
		case strings.HasPrefix(f, "impl/runtime/"), strings.HasPrefix(f, "bindings/"):
			return "运行时线"
		}
	}
	for _, f := range files {
		if strings.HasPrefix(f, "xnull/") {
			return "发布线"
		}
	}
	for _, f := range files {
		if strings.HasPrefix(f, "evidence/") || strings.HasPrefix(f, "收件箱/") {
			return "QA 线"
		}
	}
	return "其它"
}

func loadCommits(root, sinceISO string) ([]commitInfo, error) {
	out, err := gitOutput(root, "log", "--format=%h%x1f%an%x1f%aI%x1f%s", "--since="+sinceISO)
	if err != nil {
		return nil, err
	}
	var commits []commitInfo
	for _, line := range strings.Split(out, "\n") {
		if line == "" {
			continue
		}
		cells := strings.SplitN(line, "\x1f", 4)
		if len(cells) < 4 {
			continue
		}
		when, err := time.Parse(time.RFC3339, cells[2])
		if err != nil {
			return nil, fmt.Errorf("提交时间解析失败：%v", err)
		}
		c := commitInfo{sha: cells[0], author: cells[1], when: when, subject: cells[3]}
		if files, err := gitOutput(root, "show", "--name-only", "--format=", c.sha); err == nil {
			for _, f := range strings.Split(files, "\n") {
				if f != "" {
					c.files = append(c.files, f)
				}
			}
		}
		commits = append(commits, c)
	}
	return commits, nil
}

func loadEvidence(dir string) ([]evidenceInfo, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var out []evidenceInfo
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		info := evidenceInfo{name: e.Name()}
		_ = filepath.WalkDir(filepath.Join(dir, e.Name()), func(p string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return nil
			}
			info.files++
			if st, err := d.Info(); err == nil && st.ModTime().After(info.mtime) {
				info.mtime = st.ModTime()
			}
			return nil
		})
		out = append(out, info)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].mtime.Equal(out[j].mtime) {
			return out[i].name < out[j].name
		}
		return out[i].mtime.After(out[j].mtime)
	})
	return out, nil
}

// gateProgress 从 evidence 卡数推导门进度（SSOT 数据源），并附加门文件（若存在）。
func gateProgress(evidence []evidenceInfo, root string) []string {
	counts := map[string]int{}
	for _, e := range evidence {
		switch {
		case strings.HasPrefix(e.name, "B0") || strings.HasPrefix(e.name, "M6-B0"):
			counts["B0"]++
		case strings.HasPrefix(e.name, "B1") || strings.HasPrefix(e.name, "M6-B1"):
			counts["B1"]++
		case strings.HasPrefix(e.name, "B2") || strings.HasPrefix(e.name, "M6-B2"):
			counts["B2"]++
		case strings.HasPrefix(e.name, "B3") || strings.HasPrefix(e.name, "M6-B3"):
			counts["B3"]++
		case strings.HasPrefix(e.name, "B4") || strings.HasPrefix(e.name, "M6-B4"):
			counts["B4"]++
		}
	}
	var parts []string
	for _, gate := range []string{"B0", "B1", "B2", "B3", "B4"} {
		parts = append(parts, fmt.Sprintf("%s %d 卡", gate, counts[gate]))
	}
	out := []string{strings.Join(parts, " / ")}
	out = append(out, loadGates(root)...)
	return out
}

// loadGates 扫描门证据文件（收件箱下 *门*.md）并按名字排序。
func loadGates(root string) []string {
	var gates []string
	_ = filepath.WalkDir(filepath.Join(root, "收件箱"), func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			if d.Name() == "_归档" {
				return filepath.SkipDir
			}
			return nil
		}
		name := d.Name()
		if strings.HasSuffix(name, ".md") && strings.Contains(name, "门") {
			rel, relErr := filepath.Rel(root, p)
			if relErr == nil {
				gates = append(gates, filepath.ToSlash(rel))
			}
		}
		return nil
	})
	sort.Strings(gates)
	return gates
}

func runTests(implDir string) testSummary {
	t := testSummary{ran: true}
	cmd := exec.Command("go", "test", "./...", "-count=1", "-timeout", "300s")
	cmd.Dir = implDir
	out, err := cmd.CombinedOutput()
	t.green = err == nil
	for _, line := range strings.Split(string(out), "\n") {
		switch {
		case strings.HasPrefix(line, "ok  \t"):
			t.okPkgs++
		case strings.HasPrefix(line, "FAIL\t"), strings.HasPrefix(line, "FAIL "):
			fields := strings.Fields(line)
			if len(fields) >= 2 {
				t.failPkgs = append(t.failPkgs, fields[1])
			}
		}
	}
	return t
}

func countPass(tsv string) int {
	n := 0
	for _, line := range splitLines(tsv) {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		cells := strings.Split(line, "\t")
		if len(cells) >= 3 && cells[2] == "PASS" {
			n++
		}
	}
	return n
}

func gitOutput(root string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = root
	out, err := cmd.Output()
	return string(out), err
}

func gitLine(root string, args ...string) (string, error) {
	out, err := gitOutput(root, args...)
	return strings.TrimSpace(out), err
}

func gitShow(root, sha, path string) (string, error) {
	return gitOutput(root, "show", sha+":"+path)
}
