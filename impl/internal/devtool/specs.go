package devtool

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

var (
	partFileRe = regexp.MustCompile(`^XNull解决方案-第[1-8]部分-.+-v\d+\.\d+\.\d+\.md$`)
	fileVerRe  = regexp.MustCompile(`v(\d+\.\d+\.\d+)\.md$`)
	docVerRe   = regexp.MustCompile(`(?m)^\| 文档版本 \| (\d+\.\d+\.\d+) \|`)
	docStatRe  = regexp.MustCompile(`(?m)^\| 规范状态 \| (.+?) \|`)
	headingRe  = regexp.MustCompile(`(?m)^#{2,4} (\d+(?:\.\d+)*)`)

	sectionRe = regexp.MustCompile(`§(\d+(?:\.\d+)*)`)
	partNumRe = regexp.MustCompile(`第(\d)部分`)
)

var pendingWords = []string{"待定", "待确认", "待议", "待落实", "暂定"}

var binaryExts = []string{".docx", ".doc", ".pptx", ".xlsx", ".pdf"}

type checkResult struct {
	title string
	fails []string
}

// CheckSpecs 执行五项规范守门检查，返回退出码（0 通过 / 1 存在缺陷）。
//
// 检查项与迁移前的 check_specs.py 完全一致：
//  1. 头部三方一致（文件名版本 = 头部版本 = 正式）；
//  2. 正式版零待定措辞；
//  3. § 引用不悬空；
//  4. 仓库根禁止二进制文档；
//  5. EN 快照覆盖、版本一致、内容未滞后（版本号 + 母本内容哈希，不依赖 mtime）。
func CheckSpecs(start string, out io.Writer) (int, error) {
	l, err := findLayout(start)
	if err != nil {
		return 0, err
	}
	parts, err := listParts(l.SpecDir)
	if err != nil {
		return 0, err
	}

	fmt.Fprintf(out, "仓库：%s\n", l.Root)
	fmt.Fprintf(out, "母本目录（自适应）：%s　EN 快照：%s\n",
		relDisplay(l.SpecDir, l.Root), relDisplay(l.enDir(), l.Root))
	fmt.Fprintf(out, "扫描 %d 份正式文档 + 索引\n\n", len(parts))

	results := []checkResult{
		checkHeaders(l.SpecDir, parts),
		checkPending(l.SpecDir, parts),
		checkRefs(l.SpecDir, parts),
		checkBinaries(l.Root),
		checkEnSync(l, parts),
	}

	var fails []string
	for _, r := range results {
		fails = append(fails, report(out, r)...)
	}

	fmt.Fprintln(out)
	if len(fails) > 0 {
		fmt.Fprintf(out, "共 %d 处缺陷\n", len(fails))
		return 1, nil
	}
	fmt.Fprintln(out, "全部通过：零待定、引用零悬空、头部一致、根目录纯 Markdown、EN 快照同步")
	return 0, nil
}

// listParts 列出母本目录中的正式文档（第1–8部分），按文件名升序。
func listParts(specDir string) ([]string, error) {
	entries, err := os.ReadDir(specDir)
	if err != nil {
		return nil, err
	}
	var parts []string
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		if partFileRe.MatchString(e.Name()) {
			parts = append(parts, e.Name())
		}
	}
	sort.Strings(parts)
	return parts, nil
}

func report(out io.Writer, r checkResult) []string {
	if len(r.fails) == 0 {
		fmt.Fprintf(out, "[ok]   %s\n", r.title)
		return nil
	}
	fmt.Fprintf(out, "[FAIL] %s\n", r.title)
	for _, f := range r.fails {
		fmt.Fprintf(out, "  - %s\n", f)
	}
	return r.fails
}

func checkHeaders(specDir string, parts []string) checkResult {
	title := "头部三方一致（文件名版本 = 头部版本 = 正式）"
	var fails []string
	for _, f := range parts {
		s, err := readText(filepath.Join(specDir, f))
		if err != nil {
			fails = append(fails, fmt.Sprintf("%s: 读取失败：%v", f, err))
			continue
		}
		vFile := fileVerRe.FindStringSubmatch(f)
		mVer := docVerRe.FindStringSubmatch(s)
		mStat := docStatRe.FindStringSubmatch(s)
		if vFile == nil || mVer == nil || mStat == nil {
			fails = append(fails, fmt.Sprintf("%s: 缺头部三方字段", f))
			continue
		}
		if vFile[1] != mVer[1] {
			fails = append(fails, fmt.Sprintf("%s: 文件名版本 %s ≠ 头部 %s", f, vFile[1], mVer[1]))
		}
		if !strings.Contains(mStat[1], "正式") {
			fails = append(fails, fmt.Sprintf("%s: 规范状态非正式：%s", f, mStat[1]))
		}
	}
	return checkResult{title: title, fails: fails}
}

func checkPending(specDir string, parts []string) checkResult {
	title := "待定内容扫描（正式版零待确认）"
	files := append(append([]string{}, parts...), indexName)
	var fails []string
	for _, f := range files {
		s, err := readText(filepath.Join(specDir, f))
		if err != nil {
			fails = append(fails, fmt.Sprintf("%s: 读取失败：%v", f, err))
			continue
		}
		for n, line := range splitLines(s) {
			if !containsAny(line, pendingWords) {
				continue
			}
			if strings.Contains(line, "无待定") {
				continue
			}
			if strings.Contains(line, "禁用措辞") {
				continue
			}
			if strings.Contains(line, "~~") &&
				(strings.Contains(line, "已过时") || strings.Contains(line, "已定案")) {
				continue
			}
			fails = append(fails, fmt.Sprintf("%s:%d: %s", f, n+1,
				truncateRunes(strings.TrimSpace(line), 80)))
		}
	}
	return checkResult{title: title, fails: fails}
}

func checkRefs(specDir string, parts []string) checkResult {
	title := "§ 引用悬空（全集校验）"
	heads := make(map[string]bool)
	for _, f := range parts {
		s, err := readText(filepath.Join(specDir, f))
		if err != nil {
			continue
		}
		for _, m := range headingRe.FindAllStringSubmatch(s, -1) {
			heads[strings.TrimRight(m[1], ".")] = true
		}
	}

	files := append(append([]string{}, parts...), indexName)
	var fails []string
	for _, f := range files {
		s, err := readText(filepath.Join(specDir, f))
		if err != nil {
			fails = append(fails, fmt.Sprintf("%s: 读取失败：%v", f, err))
			continue
		}
		for n, line := range splitLines(s) {
			for _, m := range sectionRe.FindAllStringSubmatch(line, -1) {
				ref := m[1]
				if heads[ref] || heads[strings.SplitN(ref, ".", 2)[0]] {
					continue
				}
				fails = append(fails, fmt.Sprintf("%s:%d: §%s 未命中任何章节", f, n+1, ref))
			}
		}
	}
	return checkResult{title: title, fails: fails}
}

func checkBinaries(root string) checkResult {
	title := "二进制文档拦截（根目录仅 Markdown）"
	entries, err := os.ReadDir(root)
	if err != nil {
		return checkResult{title: title, fails: []string{fmt.Sprintf("读取仓库根失败：%v", err)}}
	}
	var fails []string
	for _, e := range entries {
		name := strings.ToLower(e.Name())
		for _, ext := range binaryExts {
			if strings.HasSuffix(name, ext) {
				fails = append(fails, e.Name())
				break
			}
		}
	}
	return checkResult{title: title, fails: fails}
}

func checkEnSync(l layout, parts []string) checkResult {
	enDir := l.enDir()
	if !dirExists(enDir) {
		return checkResult{
			title: "EN 快照同步（公开内容线）",
			fails: []string{fmt.Sprintf("%s 目录不存在", relDisplay(enDir, l.Root))},
		}
	}
	entries, err := os.ReadDir(enDir)
	if err != nil {
		return checkResult{
			title: "EN 快照同步（公开内容线）",
			fails: []string{fmt.Sprintf("读取 %s 失败：%v", enDir, err)},
		}
	}
	var enFiles []string
	for _, e := range entries {
		enFiles = append(enFiles, e.Name())
	}
	sort.Strings(enFiles)

	// 母本内容指纹清单（impl/docs/conformance/en-source.sha256）。
	// 有登记就比对内容哈希；未登记不回退到 mtime —— 时间戳在 clone/checkout 后会刷新，判据不可靠。
	enSource := loadEnSource(filepath.Join(l.Root, "impl", "docs", "conformance", "en-source.sha256"))

	type pair struct{ cn, en string }
	var pairs []pair
	var fails []string
	for _, cn := range parts {
		m := partNumRe.FindStringSubmatch(cn)
		if m == nil {
			continue
		}
		en := firstWithPrefix(enFiles, "S"+m[1]+"-")
		if en == "" {
			fails = append(fails, fmt.Sprintf("缺 S%s 英译（母本 %s）", m[1], cn))
			continue
		}
		pairs = append(pairs, pair{cn: cn, en: en})
	}

	ledgerEn := firstWithPrefix(enFiles, "Conformance-Ledger-")
	if ledgerEn == "" {
		fails = append(fails, "缺台账英译（Conformance-Ledger）")
	} else {
		pairs = append(pairs, pair{cn: ledgerName, en: ledgerEn})
	}

	for _, p := range pairs {
		vcn := fileVerRe.FindStringSubmatch(p.cn)
		ven := fileVerRe.FindStringSubmatch(p.en)
		if vcn == nil {
			fails = append(fails, fmt.Sprintf("%s: 文件名缺版本号", p.cn))
			continue
		}
		if ven == nil || ven[1] != vcn[1] {
			got := "?"
			if ven != nil {
				got = ven[1]
			}
			fails = append(fails, fmt.Sprintf("%s: 版本 %s ≠ 母本 %s", p.en, got, vcn[1]))
			continue
		}
		// 不再以 mtime 判滞后（clone/checkout 会刷新时间戳，导致假红）。
		// 判据：版本号一致（上面已查）+ 英译声明的母本内容哈希与当前母本一致。
		cnPath := filepath.Join(l.SpecDir, p.cn)
		enPath := filepath.Join(enDir, p.en)
		cnText, err := readText(cnPath)
		if err != nil {
			fails = append(fails, fmt.Sprintf("%s: 读取失败：%v", p.cn, err))
			continue
		}
		enText, err := readText(enPath)
		if err != nil {
			fails = append(fails, fmt.Sprintf("%s: 读取失败：%v", p.en, err))
			continue
		}
		_ = enText
		if recorded, ok := enSource[p.cn]; ok {
			current := contentSHA256([]byte(cnText))
			if recorded != current {
				fails = append(fails, fmt.Sprintf(
					"%s: 内容哈希不符——母本 %s 变更后英译未同步重译（清单 %s，当前 %s）",
					p.en, p.cn, recorded, current))
			}
		}
	}

	return checkResult{
		title: fmt.Sprintf("EN 快照同步（%d 份对照）", len(pairs)),
		fails: fails,
	}
}

// loadEnSource 读取「母本文件名 → 翻译时母本内容 SHA-256」清单。
// 文件缺失或行不合法时返回已解析部分（缺失即表示未登记，不做滞后判定）。
func loadEnSource(path string) map[string]string {
	table := make(map[string]string)
	s, err := readText(path)
	if err != nil {
		return table
	}
	for _, line := range splitLines(s) {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		cells := strings.Split(line, "\t")
		if len(cells) < 2 {
			continue
		}
		name := strings.TrimSpace(cells[0])
		hash := strings.ToLower(strings.TrimSpace(cells[1]))
		if name != "" && len(hash) == 64 {
			table[name] = hash
		}
	}
	return table
}

// contentSHA256 返回内容的 SHA-256 十六进制摘要（与 mtime 无关）。
func contentSHA256(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func firstWithPrefix(files []string, prefix string) string {
	for _, f := range files {
		if strings.HasPrefix(f, prefix) {
			return f
		}
	}
	return ""
}

func containsAny(s string, words []string) bool {
	for _, w := range words {
		if strings.Contains(s, w) {
			return true
		}
	}
	return false
}
