package devtool

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

type ledgerDoc struct {
	id   string
	stem string
}

// 文档顺序即台账统计中「按文档」的展示顺序。
var ledgerDocs = []ledgerDoc{
	{"S1", "第1部分-基础语法"},
	{"S2", "第2部分-对象编程"},
	{"S3", "第3部分-内存管理"},
	{"S4", "第4部分-错误处理"},
	{"S5", "第5部分-运行时任务与并发"},
	{"S6", "第6部分-标准库XDK"},
	{"S7", "第7部分-FFI"},
	{"S8", "第8部分-工程配置"},
}

// 编号前缀 → 实现里程碑。
var ledgerMilestone = map[string]string{
	"LEX": "M1", "EXPR": "M1", "STMT": "M1", "BLOCK": "M1", "CTRL": "M1",
	"TYPE": "M1", "FIELD": "M1", "INH": "M1", "PROTO": "M1", "STRUCT": "M1",
	"ENUM": "M1", "TUPLE": "M1", "GEN": "M1", "INT": "M1", "KIND": "M1",
	"DISP": "M1", "ENTRY": "M1", "PKG": "M1", "ANN": "M1",
	"MEM": "M2", "DET": "M2", "CLEAN": "M2", "GATE": "M2", "BND": "M2",
	"BOUND": "M2", "ERR": "M2", "OBS": "M2", "CANCEL": "M2", "NEG": "M2",
	"TASK": "M2", "SYNC": "M2", "SCHED": "M2", "PCTOR": "M2",
	"XDK": "M3", "FFI": "M3", "BLD": "M3", "EXT": "M3", "SINGLE": "M3",
	"PROJ": "M0/M3",
}

var (
	ledgerRowRe = regexp.MustCompile(`^\|\s*([A-Z]{2,6})-(\d{2,3})\s*\|(.*)$`)
	spaceRe     = regexp.MustCompile(`\s+`)
)

type ledgerItem struct {
	doc  string
	id   string
	text string
	ms   string
}

type statusEntry struct {
	file  string
	state string
}

// GenerateLedger 从规范母本抽取验收编号行，生成《一致性用例台账》。
func GenerateLedger(start string, out io.Writer) error {
	l, err := findLayout(start)
	if err != nil {
		return err
	}
	docs, err := ledgerDocFiles(l.SpecDir)
	if err != nil {
		return err
	}
	items, err := ledgerRows(l.SpecDir, docs)
	if err != nil {
		return err
	}

	var uniq []ledgerItem
	seen := make(map[string]bool)
	for _, it := range items {
		if seen[it.id] {
			continue
		}
		seen[it.id] = true
		uniq = append(uniq, it)
	}

	byDoc := make(map[string]int)
	var docOrder []string
	byMS := make(map[string]int)
	for _, it := range uniq {
		if byDoc[it.doc] == 0 {
			docOrder = append(docOrder, it.doc)
		}
		byDoc[it.doc]++
		byMS[it.ms]++
	}

	status, err := loadStatus(filepath.Join(l.Root, "impl", "docs", "conformance", "status.tsv"))
	if err != nil {
		return err
	}
	passed := 0
	for _, v := range status {
		if v.state == "PASS" {
			passed++
		}
	}

	lines := []string{
		"# XNull 一致性用例台账",
		"",
		"> 由 `xnull dev ledger` 自动生成，**不要手改编号列**。人工只维护两列：`用例文件`（相对 `impl/Tests/`）与`状态`。",
		"> 状态取值：`未实现` / `部分` / `PASS` / `N/A（非承诺或被否决，见对应文档）`。",
		"> 台账是实现的单一事实源：任何里程碑宣告完成，必须先把对应行的状态改为 `PASS`。",
		"> 旁表口径：`status.tsv` 只登记有实现证据的锚点（未登记行在台账中显示 `未实现`）；101 锚点与旁表行的逐条映射、理由与重登条件见 `impl/docs/conformance/ledger-restructure.md`。",
		"",
		"## 0. 统计",
		"",
		"| 维度 | 分布 |",
		"| --- | --- |",
		fmt.Sprintf("| 总计 | %d 条（PASS %d） |", len(uniq), passed),
		"| 按文档 | " + joinCounts(docOrder, byDoc) + " |",
		"| 按里程碑 | " + joinCounts(sortedKeys(byMS), byMS) + " |",
		"",
		"## 1. 用例清单",
		"",
		"| 编号 | 文档 | 验收要点 | 里程碑 | 用例文件 | 状态 |",
		"| --- | --- | --- | --- | --- | --- |",
	}
	for _, it := range uniq {
		text := strings.ReplaceAll(it.text, "|", `\|`)
		st, ok := status[it.id]
		if !ok {
			st = statusEntry{file: "—", state: "未实现"}
		}
		lines = append(lines, fmt.Sprintf("| %s | %s | %s | %s | %s | %s |",
			it.id, it.doc, text, it.ms, st.file, st.state))
	}

	outPath := filepath.Join(l.SpecDir, ledgerName)
	if err := os.WriteFile(outPath, []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
		return err
	}
	fmt.Fprintf(out, "已生成 %s：%d 条；按文档 %s；按里程碑 %s\n",
		outPath, len(uniq), pyDict(docOrder, byDoc), pyDict(sortedKeys(byMS), byMS))
	return nil
}

func ledgerDocFiles(specDir string) ([]ledgerDoc, error) {
	entries, err := os.ReadDir(specDir)
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)

	var docs []ledgerDoc
	for _, d := range ledgerDocs {
		found := ""
		for _, name := range names {
			if strings.Contains(name, d.stem) && strings.HasSuffix(name, ".md") {
				found = name
				break
			}
		}
		if found == "" {
			return nil, fmt.Errorf("缺少 %s 母本（%s）", d.id, d.stem)
		}
		docs = append(docs, ledgerDoc{id: d.id, stem: found})
	}
	return docs, nil
}

func ledgerRows(specDir string, docs []ledgerDoc) ([]ledgerItem, error) {
	var items []ledgerItem
	for _, d := range docs {
		s, err := readText(filepath.Join(specDir, d.stem))
		if err != nil {
			return nil, err
		}
		for _, line := range splitLines(s) {
			m := ledgerRowRe.FindStringSubmatch(strings.TrimSpace(line))
			if m == nil {
				continue
			}
			var cells []string
			for _, c := range strings.Split(m[3], "|") {
				c = strings.TrimSpace(c)
				if c == "" || strings.Trim(c, "-") == "" {
					continue
				}
				cells = append(cells, c)
			}
			if len(cells) == 0 {
				continue
			}
			text := strings.Join(cells, "；")
			text = strings.ReplaceAll(text, "<br>", "；")
			text = spaceRe.ReplaceAllString(text, " ")
			text = strings.Trim(text, " ；")
			ms := ledgerMilestone[m[1]]
			if ms == "" {
				ms = "M3"
			}
			items = append(items, ledgerItem{
				doc:  d.id,
				id:   m[1] + "-" + m[2],
				text: text,
				ms:   ms,
			})
		}
	}
	return items, nil
}

func loadStatus(path string) (map[string]statusEntry, error) {
	table := make(map[string]statusEntry)
	s, err := readText(path)
	if os.IsNotExist(err) {
		return table, nil
	}
	if err != nil {
		return nil, err
	}
	for _, line := range splitLines(s) {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		cells := strings.Split(line, "\t")
		if len(cells) < 3 {
			continue
		}
		table[cells[0]] = statusEntry{file: cells[1], state: cells[2]}
	}
	return table, nil
}

func joinCounts(order []string, counts map[string]int) string {
	parts := make([]string, 0, len(order))
	for _, k := range order {
		parts = append(parts, fmt.Sprintf("%s %d", k, counts[k]))
	}
	return strings.Join(parts, " · ")
}

func sortedKeys(m map[string]int) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func pyDict(order []string, counts map[string]int) string {
	parts := make([]string, 0, len(order))
	for _, k := range order {
		parts = append(parts, fmt.Sprintf("'%s': %d", k, counts[k]))
	}
	return "{" + strings.Join(parts, ", ") + "}"
}
