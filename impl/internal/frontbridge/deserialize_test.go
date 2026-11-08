package frontbridge

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	return root
}

func corpusSources(t *testing.T) []string {
	t.Helper()
	root := repoRoot(t)
	f, err := os.Open(filepath.Join(root, "tests", "b2", "corpus.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	var out []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) != 2 {
			continue
		}
		out = append(out, filepath.Join(root, parts[1]))
	}
	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}
	return out
}

// TestDeserializeRoundTrip 验证反序列化对全语料保持 PrintUnitPos 逐字节一致。
func TestDeserializeRoundTrip(t *testing.T) {
	files := corpusSources(t)
	extra, _ := filepath.Glob(filepath.Join(repoRoot(t), "tests", "b2", "parser_cases", "*.x"))
	files = append(files, extra...)
	if len(files) == 0 {
		t.Fatal("语料为空")
	}
	for _, path := range files {
		src, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("%s: %v", path, err)
		}
		u, ds := xfront.ParseUnit(path, string(src))
		if len(ds) > 0 {
			t.Fatalf("%s: oracle 诊断非空：%s", path, ds[0].String())
		}
		want := xfront.PrintUnitPos(u)
		if strings.Contains(want, "(depth-limit)") {
			// 传输层截断：Deserialize 必须拒绝，工具链按失败回退 Go oracle。
			if _, err := Deserialize(want); err == nil {
				t.Fatalf("%s: depth-limit dump 不应被接受", path)
			}
			continue
		}
		got, err := Deserialize(want)
		if err != nil {
			t.Fatalf("%s: 反序列化失败：%v", path, err)
		}
		if re := xfront.PrintUnitPos(got); re != want {
			i := 0
			for i < len(re) && i < len(want) && re[i] == want[i] {
				i++
			}
			t.Fatalf("%s: 往返不一致（首个差异 @%d）\n want: %s\n  got: %s",
				path, i, clip(want, i), clip(re, i))
		}
	}
}

func clip(s string, i int) string {
	lo := i - 80
	if lo < 0 {
		lo = 0
	}
	hi := i + 160
	if hi > len(s) {
		hi = len(s)
	}
	return s[lo:hi]
}

func TestDeserializeRejectsBadInput(t *testing.T) {
	for _, bad := range []string{"", "(", "(xnast v1", "(xnast v1 (NoSuchNode))"} {
		if _, err := Deserialize(bad); err == nil {
			t.Fatalf("期望失败：%q", bad)
		}
	}
}
