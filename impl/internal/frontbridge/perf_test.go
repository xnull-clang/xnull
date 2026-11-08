package frontbridge

import (
	"os"
	"path/filepath"
	"sync"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// TestAutoNeverRunsInProcess 锁死性能约束：auto 生产路径绝不调用进程内解释器。
func TestAutoNeverRunsInProcess(t *testing.T) {
	t.Setenv("XNULL_FRONTEND", "auto")
	t.Setenv("XNULL_NATIVE_XPARSER", "")
	t.Setenv("XNULL_SELFHOST_BIN", "")
	t.Setenv("XNULL_BIN", "")
	t.Setenv("XNULL_FRONTEND_AUTOBUILD", "0")
	nativeOnce = sync.Once{}
	nativeBin, nativeErr = "", nil

	inprocOnce.Do(func() {})
	oldOK := inprocOK
	inprocOK = true
	defer func() { inprocOK = oldOK }()

	inprocMu.Lock()
	inprocCalls = 0
	inprocMu.Unlock()

	ParseUnit("t.x", "static Int main() { return 0 }\n")

	inprocMu.Lock()
	n := inprocCalls
	inprocMu.Unlock()
	if n != 0 {
		t.Fatalf("auto 模式调用了进程内解释器 %d 次（应只走原生二进制/Go）", n)
	}
}

// TestASTCacheMemoryAndDisk 验证同一源码第二次命中进程内缓存，清空内存后命中磁盘缓存。
func TestASTCacheMemoryAndDisk(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XNULL_FRONTBRIDGE_CACHE", dir)
	parser := filepath.Join(dir, "fake-xparser.x")
	if err := os.WriteFile(parser, []byte("// fake parser\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XNULL_SELFHOST_XPARSER", parser)
	fakeNative := filepath.Join(dir, "fake-native")
	if err := os.WriteFile(fakeNative, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XNULL_NATIVE_XPARSER", fakeNative)

	nativeOnce = sync.Once{}
	nativeBin, nativeErr = "", nil
	astCache = newLRU(256)

	calls := 0
	oldRunner := nativeRunner
	nativeRunner = func(string, ...string) (string, error) {
		calls++
		return "(xnast v1 (CompilationUnit (P (Pos (Line 1) (Col 1))) (Package (nil)) (Imports (slice)) (Decls (slice))))", nil
	}
	defer func() { nativeRunner = oldRunner }()

	src := "static Int main() { return 0 }\n"
	if _, err := parserAST(src, modeAuto); err != nil {
		t.Fatal(err)
	}
	if _, err := parserAST(src, modeAuto); err != nil {
		t.Fatal(err)
	}
	if calls != 1 {
		t.Fatalf("进程内缓存未命中：calls=%d", calls)
	}

	astCache = newLRU(256) // 丢弃内存缓存，只保留磁盘
	if _, err := parserAST(src, modeAuto); err != nil {
		t.Fatal(err)
	}
	if calls != 1 {
		t.Fatalf("磁盘缓存未命中：calls=%d", calls)
	}
}

// TestParseBatchMatchesSingle 验证批量解析与逐文件解析结果一致且顺序稳定。
func TestParseBatchMatchesSingle(t *testing.T) {
	root := repoRoot(t)
	paths, _ := filepath.Glob(filepath.Join(root, "tests", "b2", "parser_cases", "*.x"))
	if len(paths) == 0 {
		t.Fatal("缺少 parser_cases")
	}
	var sources []Source
	for _, p := range paths {
		b, err := os.ReadFile(p)
		if err != nil {
			t.Fatal(err)
		}
		sources = append(sources, Source{File: p, Src: string(b)})
	}
	batch := ParseBatch(sources)
	if len(batch) != len(sources) {
		t.Fatalf("批量结果数量 %d != %d", len(batch), len(sources))
	}
	for i, s := range sources {
		u, ds := ParseUnit(s.File, s.Src)
		if len(ds) > 0 {
			t.Fatalf("%s: %s", s.File, ds[0].String())
		}
		if xfront.PrintUnitPos(batch[i].Unit) != xfront.PrintUnitPos(u) {
			t.Fatalf("%s: 批量结果与单文件不一致", s.File)
		}
	}
}

// TestAutoUsesNativeParser 验证 auto 有原生二进制时确实使用它（而不是 Go oracle）。
func TestAutoUsesNativeParser(t *testing.T) {
	dir := t.TempDir()
	dump := "(xnast v1 (CompilationUnit (P (Pos (Line 7) (Col 3))) (Package (nil)) (Imports (slice)) (Decls (slice))))"
	dumpFile := filepath.Join(dir, "dump.txt")
	if err := os.WriteFile(dumpFile, []byte(dump+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	native := filepath.Join(dir, "fake-native")
	script := "#!/bin/sh\ncat " + dumpFile + "\n"
	if err := os.WriteFile(native, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XNULL_FRONTEND", "auto")
	t.Setenv("XNULL_NATIVE_XPARSER", native)
	t.Setenv("XNULL_FRONTBRIDGE_CACHE", filepath.Join(dir, "cache"))
	t.Setenv("XNULL_FRONTEND_AUTOBUILD", "0")
	nativeOnce = sync.Once{}
	nativeBin, nativeErr = "", nil
	astCache = newLRU(256)

	u, ds := ParseUnit("t.x", "static Int main() { return 0 }\n")
	if len(ds) > 0 {
		t.Fatalf("诊断：%s", ds[0].String())
	}
	if got := xfront.PrintUnitPos(u); got != dump {
		t.Fatalf("未使用原生 parser 的 AST：\n got=%s", got)
	}
}

// TestNativeParserAutobuild 验证“构建一次并缓存”：工具链只调用一次。
func TestNativeParserAutobuild(t *testing.T) {
	dir := t.TempDir()
	parser := filepath.Join(dir, "xparser.x")
	if err := os.WriteFile(parser, []byte("// parser\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	calls := filepath.Join(dir, "calls.txt")
	tool := filepath.Join(dir, "fake-xnull")
	script := "#!/bin/sh\n" +
		"echo x >> " + calls + "\n" +
		"printf '#!/bin/sh\\ncat\\n' > \"$4\"\n" +
		"chmod +x \"$4\"\n"
	if err := os.WriteFile(tool, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XNULL_FRONTBRIDGE_CACHE", filepath.Join(dir, "cache"))
	t.Setenv("XNULL_SELFHOST_XPARSER", parser)
	t.Setenv("XNULL_TOOLCHAIN_BIN", tool)
	t.Setenv("XNULL_FRONTEND_AUTOBUILD", "1")
	t.Setenv("XNULL_NATIVE_XPARSER", "")
	nativeOnce = sync.Once{}
	nativeBin, nativeErr = "", nil

	first, err := nativeParser()
	if err != nil {
		t.Fatalf("自动构建失败：%v", err)
	}
	second, err := nativeParser()
	if err != nil || first != second {
		t.Fatalf("第二次解析应命中缓存：%q %q %v", first, second, err)
	}
	b, err := os.ReadFile(calls)
	if err != nil {
		t.Fatal(err)
	}
	if string(b) != "x\n" {
		t.Fatalf("工具链调用次数异常：%q", string(b))
	}
}
