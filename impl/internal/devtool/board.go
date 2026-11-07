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
	Since       time.Duration // 统计窗口，缺省 7 天
	RunTests    bool          // 是否现场跑 go test ./...
	RecordGreen bool          // 测试绿时把 HEAD 记为每条线的 last-green
	Now         time.Time     // 注入时间（测试用）
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
	greenNote := ""
	if opts.RecordGreen && opts.RunTests {
		if tests.green {
			notes, err := recordLastGreen(root, head, implDir, opts.Now)
			if err != nil {
				return err
			}
			for _, n := range notes {
				greenNote += "> last-green 未推进：" + n + "\n"
			}
			if greenNote != "" {
				greenNote += "\n"
			}
		} else {
			greenNote = "> 测试红：未更新 last-green（ADR-003）\n\n"
		}
	}

	evidence, err := loadEvidence(filepath.Join(root, "evidence"))
	if err != nil {
		return err
	}
	gates := gateProgress(evidence, root)
	lastGreen := loadLastGreen(filepath.Join(root, "handoff", "last-green.tsv"))
	handoffs := loadHandoffs(filepath.Join(root, "handoff"))

	var b strings.Builder
	fmt.Fprintf(&b, "# SSOT 看板（脚本生成，手改即作废）\n\n")
	fmt.Fprintf(&b, "- 生成时间：%s\n", opts.Now.Format("2006-01-02 15:04:05 -0700"))
	fmt.Fprintf(&b, "- 仓库：`%s`　分支：`%s`　HEAD：`%s`\n", filepath.Base(root), branch, head)
	fmt.Fprintf(&b, "- 窗口：近 %s（起点提交 `%s`）\n", humanDuration(opts.Since), windowStart)
	fmt.Fprintf(&b, "- 数据源：git log / go test / impl/docs/conformance/status.tsv / evidence/ / handoff/\n")
	fmt.Fprintf(&b, "- 断链协议：ADR-003（接力棒 + last-green；`--record-green` 在测试绿时记录 HEAD）\n\n")
	b.WriteString(greenNote)

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

	// 断链与最后绿点（ADR-003）
	fmt.Fprintf(&b, "## 断链与最后绿点（ADR-003）\n\n")
	fmt.Fprintf(&b, "| 线 | last-green | 落后 HEAD | 状态 | 最近 commit |\n|---|---|---|---|---|\n")
	warnings := []string{}
	for _, ln := range boardLines {
		lg := lastGreen[ln.name]
		status := "缺失"
		if lg.sha != "" {
			if isAncestor(root, lg.sha, head) {
				status = "有效"
			} else {
				status = "失效（非 HEAD 祖先）"
			}
		}
		latestAge := "—"
		latestCommit := "—"
		for i := len(commits) - 1; i >= 0; i-- {
			if lineOf(commits[i].files) == ln.name {
				d := opts.Now.Sub(commits[i].when)
				latestCommit = commits[i].sha + "（" + humanAge(d) + "）"
				if d > 2*time.Hour {
					warnings = append(warnings, fmt.Sprintf("%s：%s 无 commit（ADR-003 2h 阈值）", ln.name, humanAge(d)))
				}
				latestAge = humanAge(d)
				break
			}
		}
		_ = latestAge
		if lg.sha == "" {
			warnings = append(warnings, fmt.Sprintf("%s：缺 last-green（ADR-003）", ln.name))
		} else if status != "有效" {
			warnings = append(warnings, fmt.Sprintf("%s：last-green %s 失效（不是 HEAD 祖先）", ln.name, lg.sha))
		}
		lag := "—"
		if lg.sha != "" {
			if n := commitsBetween(root, lg.sha, head); n >= 0 {
				lag = fmt.Sprintf("%d", n)
			}
		}
		note := ""
		if _, ok := lineCodePaths[ln.name]; !ok {
			note = "（支撑线：活动路径最近提交）"
		} else {
			note = "（该线最近提交）"
		}
		fmt.Fprintf(&b, "| %s | %s | %s | %s%s | %s |\n", ln.name, orDash(lg.sha), lag, status, note, latestCommit)
	}
	fmt.Fprintf(&b, "\n")

	// 接力棒（ADR-003）
	expected := expectedHandoffCards(root, evidence)
	for name := range handoffs {
		expected[name] = true
	}
	missingHandoff := 0
	fmt.Fprintf(&b, "## 接力棒（handoff/）\n\n")
	fmt.Fprintf(&b, "已有接力棒 %d 根；应覆盖卡片 %d 张。\n\n", len(handoffs), len(expected))
	if len(expected) > 0 {
		fmt.Fprintf(&b, "| 卡片 | 接力棒 | 字段 |\n|---|---|---|\n")
		names := make([]string, 0, len(expected))
		for name := range expected {
			names = append(names, name)
		}
		sort.Strings(names)
		for _, name := range names {
			h, ok := handoffs[name]
			state := "缺失"
			fieldState := "—"
			if ok {
				state = "有"
				if len(h.missing) == 0 {
					fieldState = "完整"
				} else {
					fieldState = "缺 " + strings.Join(h.missing, "、")
				}
			} else {
				missingHandoff++
				warnings = append(warnings, "接力棒缺失："+name)
			}
			fmt.Fprintf(&b, "| %s | %s | %s |\n", name, state, fieldState)
		}
		for name, h := range handoffs {
			if len(h.missing) > 0 {
				warnings = append(warnings, "接力棒缺字段："+name+"（"+strings.Join(h.missing, "、")+"）")
			}
			_ = name
		}
		fmt.Fprintf(&b, "\n")
	}

	// 告警汇总
	fmt.Fprintf(&b, "## 告警（ADR-003 断链判据）\n\n")
	sort.Strings(warnings)
	if len(warnings) == 0 {
		fmt.Fprintf(&b, "无。\n\n")
	} else {
		for _, w := range warnings {
			fmt.Fprintf(&b, "- %s\n", w)
		}
		fmt.Fprintf(&b, "\n")
	}

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

// 各生产线的代码路径（用于计算「该线最近一次随全量测试绿过的提交」）。
var lineCodePaths = map[string][]string{
	"前端线":  {"impl/internal/xfront", "impl/internal/sema"},
	"自举线":  {"impl/internal/codegen", "impl/internal/xnfmt", "impl/cmd", "impl/internal/devtool", "impl/internal/cli"},
	"运行时线": {"impl/runtime", "bindings"},
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

// gateCards 是各门的固定卡清单（死命令第 1 号 §1.3 / 门报告）。
var gateCards = map[string][]string{
	"B0": {"B0-01", "B0-02", "B0-03", "B0-04", "B0-05", "B0-06"},
	"B1": {"B1-01", "B1-02", "B1-03"},
}

// canonicalCard 把证据目录/接力棒名归一为卡片 ID（M6-B0-05-sema → B0-05）。
func canonicalCard(name string) string {
	n := strings.TrimPrefix(name, "M6-")
	n = strings.TrimSuffix(n, "-sema")
	n = strings.TrimSuffix(n, "-qa")
	if i := strings.Index(n, "-fix"); i > 0 {
		n = n[:i]
	}
	return n
}

// gateProgress 给出各门的卡总数与「有证据」卡数（数据源：evidence/ + handoff/）。
func gateProgress(evidence []evidenceInfo, root string) []string {
	have := map[string]bool{}
	for _, e := range evidence {
		have[canonicalCard(e.name)] = true
	}
	if entries, err := os.ReadDir(filepath.Join(root, "handoff")); err == nil {
		for _, e := range entries {
			if e.IsDir() || !strings.HasSuffix(e.Name(), ".md") || strings.HasPrefix(e.Name(), "_") {
				continue
			}
			have[canonicalCard(strings.TrimSuffix(e.Name(), ".md"))] = true
		}
	}
	var parts []string
	for _, gate := range []string{"B0", "B1", "B2", "B3", "B4"} {
		cards, ok := gateCards[gate]
		if !ok {
			parts = append(parts, gate+" 0 卡")
			continue
		}
		done := 0
		for _, id := range cards {
			if have[id] {
				done++
			}
		}
		parts = append(parts, fmt.Sprintf("%s %d 卡（有证据 %d）", gate, len(cards), done))
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

func orDash(s string) string {
	if s == "" {
		return "—"
	}
	return s
}

func humanAge(d time.Duration) string {
	if d < time.Minute {
		return "<1m"
	}
	if d < time.Hour {
		return fmt.Sprintf("%dm", int(d.Minutes()))
	}
	return fmt.Sprintf("%dh%02dm", int(d.Hours()), int(d.Minutes())%60)
}

// lastGreenEntry 是一条线的最后绿点。
type lastGreenEntry struct {
	line string
	sha  string
	when time.Time
}

func loadLastGreen(path string) map[string]lastGreenEntry {
	out := map[string]lastGreenEntry{}
	s, err := readText(path)
	if err != nil {
		return out
	}
	for _, line := range splitLines(s) {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		cells := strings.Split(line, "\t")
		if len(cells) < 2 {
			continue
		}
		e := lastGreenEntry{line: strings.TrimSpace(cells[0]), sha: strings.TrimSpace(cells[1])}
		if len(cells) >= 3 {
			if t, err := time.Parse(time.RFC3339, strings.TrimSpace(cells[2])); err == nil {
				e.when = t
			}
		}
		out[e.line] = e
	}
	return out
}

// recordLastGreen 逐线跑全量测试，绿的那条线才推进 last-green（脚本生成，手改即作废）。
//
// 每线 last-green 的 sha 取「该线路径最近一次提交」：本次测试在 HEAD 上跑绿，
// 即证明该提交所在线的代码当前是绿的；红则保留旧值，不推进。
func recordLastGreen(root, head, implDir string, now time.Time) ([]string, error) {
	dir := filepath.Join(root, "handoff")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	prev := loadLastGreen(filepath.Join(dir, "last-green.tsv"))
	var b strings.Builder
	b.WriteString("# 线\tlast-green\t记录时间（由 xnull dev board --record-green 生成，手改即作废）\n")
	var notes []string
	for _, ln := range boardLines {
		if ok, out := runLineTestsFn(root, implDir, ln.name); !ok {
			keep := head
			if e := prev[ln.name]; e.sha != "" {
				keep = e.sha
			}
			notes = append(notes, fmt.Sprintf("%s：测试红，last-green 保持 %s（%s）", ln.name, keep, firstLine(out)))
			fmt.Fprintf(&b, "%s\t%s\t%s\n", ln.name, keep, now.Format(time.RFC3339))
			continue
		}
		sha := head
		if got, err := gitLine(root, append([]string{"log", "-1", "--format=%h", "--"}, linePaths(ln.name)...)...); err == nil && got != "" {
			sha = got
		}
		fmt.Fprintf(&b, "%s\t%s\t%s\n", ln.name, sha, now.Format(time.RFC3339))
	}
	return notes, os.WriteFile(filepath.Join(dir, "last-green.tsv"), []byte(b.String()), 0o644)
}

// linePaths 返回该线的路径集合（含支撑线的活动目录）。
func linePaths(line string) []string {
	if p, ok := lineCodePaths[line]; ok {
		return p
	}
	switch line {
	case "QA 线":
		return []string{"evidence", "收件箱/QA1"}
	case "发布线":
		return []string{"xnull", "推广", "收件箱/COO"}
	}
	return nil
}

// runLineTestsFn 可注入（测试用），默认跑真实测试。
var runLineTestsFn = runLineTests

// runLineTests 按线跑全量测试：生产线跑各自代码包，运行时线跑 C 套件 + Go 包，支撑线跑全仓。
func runLineTests(root, implDir, line string) (bool, string) {
	if line == "运行时线" {
		cmd := exec.Command("sh", "runtime/build_rt.sh")
		cmd.Dir = implDir
		out, err := cmd.CombinedOutput()
		if err != nil {
			return false, string(out)
		}
	}
	pkgs := "./..."
	switch line {
	case "前端线":
		pkgs = existingPkgPatterns(implDir, "./internal/xfront/...", "./internal/sema/...")
	case "自举线":
		pkgs = existingPkgPatterns(implDir, "./internal/codegen/...", "./internal/xnfmt/...",
			"./cmd/...", "./internal/devtool/...", "./internal/cli/...")
	}
	cmd := exec.Command("sh", "-c", "go test -count=1 -timeout 300s "+pkgs)
	cmd.Dir = implDir
	out, err := cmd.CombinedOutput()
	return err == nil, string(out)
}

// existingPkgPatterns 过滤不存在的包（例如未合入的 xnfmt），避免 go test 因 pattern 无匹配而红。
func existingPkgPatterns(implDir string, pats ...string) string {
	var kept []string
	for _, p := range pats {
		dir := strings.TrimSuffix(strings.TrimPrefix(p, "./"), "/...")
		if st, err := os.Stat(filepath.Join(implDir, dir)); err == nil && st.IsDir() {
			kept = append(kept, p)
		}
	}
	if len(kept) == 0 {
		return "./..."
	}
	return strings.Join(kept, " ")
}

func firstLine(s string) string {
	for _, line := range strings.Split(s, "\n") {
		line = strings.TrimSpace(line)
		if line != "" && !strings.HasPrefix(line, "ok ") {
			return truncateRunes(line, 80)
		}
	}
	return ""
}

// commitsBetween 返回 sha..head 的提交数（该线落后多少个提交）。
func commitsBetween(root, sha, head string) int {
	if sha == "" || sha == head {
		return 0
	}
	out, err := gitLine(root, "rev-list", "--count", sha+".."+head)
	if err != nil {
		return -1
	}
	n := 0
	fmt.Sscanf(out, "%d", &n)
	return n
}

func isAncestor(root, sha, head string) bool {
	cmd := exec.Command("git", "merge-base", "--is-ancestor", sha, head)
	cmd.Dir = root
	return cmd.Run() == nil
}

// handoffDoc 是一根接力棒。
type handoffDoc struct {
	card    string
	missing []string
}

var handoffRequired = []string{"卡片ID", "输入", "输出文件", "commit", "验证命令", "已知缺口", "下一步"}

// loadHandoffs 解析 handoff/*.md（跳过模板与 last-green）。
func loadHandoffs(dir string) map[string]handoffDoc {
	out := map[string]handoffDoc{}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return out
	}
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || !strings.HasSuffix(name, ".md") || strings.HasPrefix(name, "_") {
			continue
		}
		data, err := readText(filepath.Join(dir, name))
		if err != nil {
			continue
		}
		card := strings.TrimSuffix(name, ".md")
		doc := handoffDoc{card: card}
		values := map[string]string{}
		current := ""
		for _, line := range splitLines(data) {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "- **") {
				rest := strings.TrimPrefix(trimmed, "- **")
				idx := strings.Index(rest, "**")
				if idx < 0 {
					continue
				}
				current = rest[:idx]
				val := strings.TrimPrefix(rest[idx+2:], "：")
				val = strings.TrimPrefix(val, ":")
				values[current] = strings.TrimSpace(val)
				continue
			}
			// 多行字段值：续行并入当前字段
			if current != "" && trimmed != "" && !strings.HasPrefix(trimmed, "#") {
				values[current] = strings.TrimSpace(values[current] + " " + trimmed)
			}
		}
		for _, key := range handoffRequired {
			val := ""
			for k, v := range values {
				if strings.HasPrefix(k, key) {
					val = v
					break
				}
			}
			if val == "" || strings.HasPrefix(val, "<") {
				doc.missing = append(doc.missing, key)
			}
		}
		out[card] = doc
	}
	return out
}

// legacyEvidencePrefixes 是 ADR-003 之前的历史证据目录：不追溯接力棒。
var legacyEvidencePrefixes = []string{"S0-", "S1-", "S2-", "S3-", "S4-", "INTEG-", "SYNC-", "D1D3E11-"}

// expectedHandoffCards 返回必须有接力棒的卡片：ADR-003 起所有非历史 evidence 卡。
// 缺棒 = 卡无效（ADR-003 §2）；历史前缀走白名单，避免追溯噪声。
func expectedHandoffCards(root string, evidence []evidenceInfo) map[string]bool {
	out := map[string]bool{}
	for _, e := range evidence {
		legacy := false
		for _, prefix := range legacyEvidencePrefixes {
			if strings.HasPrefix(e.name, prefix) {
				legacy = true
				break
			}
		}
		if !legacy {
			out[e.name] = true
		}
	}
	return out
}
