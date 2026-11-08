package frontbridge

import (
	"bytes"
	"container/list"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/interp"
	"xnull.dev/xnull/internal/xfront"
)

// 前端模式（XNULL_FRONTEND）：
//   - 未设置 / go（默认）：直接使用 Go oracle；
//   - auto：只用外部原生 xparser 二进制；没有就回退 Go，绝不在生产路径跑解释器；
//   - xnull：显式自举，允许外部/进程内解释器（测试/差分用）。
//
// B2-04b：全量 codegen 未达到 ≤170s 门禁前，默认保持 go；auto 由显式环境变量开启。
const (
	modeAuto   = "auto"
	modeXNull  = "xnull"
	modeGo     = "go"
	innerGuard = "XNULL_FRONTEND_INNER"
	buildGuard = "XNULL_FRONTEND_BUILDING"

	cacheFormat = "b2-04b-1"
)

// Source 是一个待解析的源文件（批量解析用）。
type Source struct {
	File string
	Src  string
}

// Result 是批量解析的单文件结果。
type Result struct {
	Unit  *xfront.CompilationUnit
	Diags []diag.Diagnostic
}

// ParseUnit 是 check/run/build 的统一解析入口。
//
// Go xfront 先跑一次，仅用于诊断与回退；正常文件的 AST 来自 XNull 前端。
// auto 模式下 XNull 前端只允许外部原生二进制，避免解释器拖慢生产路径。
func ParseUnit(file, src string) (*xfront.CompilationUnit, []diag.Diagnostic) {
	goUnit, goDiags := xfront.ParseUnit(file, src)
	if len(goDiags) > 0 {
		return goUnit, goDiags
	}
	mode := frontendMode()
	if mode == modeGo || os.Getenv(innerGuard) != "" || os.Getenv(buildGuard) != "" {
		return goUnit, nil
	}
	if mode == modeAuto {
		// 生产路径禁止进程内解释器：没有可用原生二进制直接回退 Go。
		if _, err := nativeParser(); err != nil {
			return goUnit, nil
		}
	}
	dump, err := parserAST(src, mode)
	if err == nil {
		if strings.Contains(dump, "(depth-limit)") {
			// dumpReflect 的 64 层截断会丢失深层子树，不能作为工具链 AST；
			// 按传输失败处理，auto 回退 Go oracle，行为与旧路径一致。
			err = fmt.Errorf("AST dump 触发 64 层 depth-limit，回退 Go oracle")
		} else if u, derr := Deserialize(dump); derr == nil {
			return u, nil
		} else {
			err = derr
		}
	}
	if mode == modeXNull {
		return nil, []diag.Diagnostic{{
			File: file, Line: 1, Col: 1, Code: "B2-001",
			Message: "XNull 前端失败：" + err.Error(),
			Hint:    "设置 XNULL_FRONTEND=go 可回退 Go 前端",
		}}
	}
	// auto：回退 Go AST，行为与旧路径一致。
	return goUnit, nil
}

// ParseBatch 批量解析多个文件（多文件工程/XDK 包集合）。
// 结果顺序与输入一致；内部按 worker 数并行，缓存命中时开销接近 Go-only。
func ParseBatch(files []Source) []Result {
	out := make([]Result, len(files))
	if len(files) == 0 {
		return out
	}
	workers := runtime.NumCPU()
	if workers > 4 {
		workers = 4
	}
	if workers > len(files) {
		workers = len(files)
	}
	if workers < 1 {
		workers = 1
	}
	jobs := make(chan int)
	var wg sync.WaitGroup
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range jobs {
				out[i].Unit, out[i].Diags = ParseUnit(files[i].File, files[i].Src)
			}
		}()
	}
	for i := range files {
		jobs <- i
	}
	close(jobs)
	wg.Wait()
	return out
}

// Tokens 用 XNull lexer 生成 L1 token dump（仅供差分测试）。
func Tokens(src string) (string, error) {
	path, err := parserFile("xlex.x", "XNULL_SELFHOST_XLEX")
	if err != nil {
		return "", err
	}
	return RunSelfhost(path, src)
}

// Diags 用 XNull parser 生成 L3 诊断序列（仅供差分测试）。
func Diags(src string) (string, error) {
	path, err := parserFile("xparser.x", "XNULL_SELFHOST_XPARSER")
	if err != nil {
		return "", err
	}
	return RunSelfhost(path, "--diags", src)
}

// RunSelfhost 运行一个自举 XNull 程序（xlex.x / xparser.x 等）。
// 优先外部解释器二进制（XNULL_SELFHOST_BIN / XNULL_BIN），否则走进程内解释器。
// 该入口只用于测试/显式自举；生产 auto 路径不会调用。
func RunSelfhost(programPath string, args ...string) (string, error) {
	bin := selfhostBin()
	if bin != "" && !sameExecutable(bin) {
		return runExternal(bin, programPath, args...)
	}
	if !inprocAvailable() {
		return "", fmt.Errorf("进程内解释器不支持 Bytes，无法运行自举前端（设置 XNULL_SELFHOST_BIN）")
	}
	return runInProcess(programPath, args...)
}

var (
	inprocOnce  sync.Once
	inprocOK    bool
	inprocCalls int
	inprocMu    sync.Mutex
)

// inprocAvailable 探测当前进程内解释器能否运行自举前端所需的最小能力（Bytes）。
// 结果按进程缓存，避免每个文件都重复失败。
func inprocAvailable() bool {
	inprocOnce.Do(func() {
		const probe = "static Int main() { Bytes b = Bytes.fromString(\"x\"); return b.length() - 1 }\n"
		u, ds := xfront.ParseUnit("frontbridge-probe.x", probe)
		if len(ds) > 0 {
			return
		}
		var out bytes.Buffer
		code, err := interp.Run(u, &out, nil)
		inprocOK = err == nil && code == 0
	})
	return inprocOK
}

func frontendMode() string {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("XNULL_FRONTEND"))) {
	case "",
		"go", "oracle":
		return modeGo
	case "auto":
		return modeAuto
	case "xnull", "selfhost":
		return modeXNull
	default:
		return modeGo
	}
}

func selfhostBin() string {
	if v := strings.TrimSpace(os.Getenv("XNULL_SELFHOST_BIN")); v != "" {
		return v
	}
	return strings.TrimSpace(os.Getenv("XNULL_BIN"))
}

func sameExecutable(bin string) bool {
	self, err := os.Executable()
	if err != nil {
		return false
	}
	a, err1 := os.Stat(self)
	b, err2 := os.Stat(bin)
	if err1 != nil || err2 != nil {
		return false
	}
	return os.SameFile(a, b)
}

func selfhostTimeout() time.Duration {
	if v := strings.TrimSpace(os.Getenv("XNULL_SELFHOST_TIMEOUT")); v != "" {
		if n, err := time.ParseDuration(v); err == nil && n > 0 {
			return n
		}
	}
	return 120 * time.Second
}

// ---- 外部执行器（解释器）----

func runExternal(bin, programPath string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), selfhostTimeout())
	defer cancel()
	cmdArgs := append([]string{"run", "--interp", programPath, "--"}, args...)
	cmd := exec.CommandContext(ctx, bin, cmdArgs...)
	cmd.Env = append(os.Environ(), innerGuard+"=1")
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return "", fmt.Errorf("XNull 前端超时（%s）", selfhostTimeout())
	}
	if err != nil {
		msg := strings.TrimSpace(errb.String())
		if msg == "" {
			return "", fmt.Errorf("XNull 前端失败：%v", err)
		}
		return "", fmt.Errorf("XNull 前端失败：%v：%s", err, msg)
	}
	return out.String(), nil
}

func runInProcess(programPath string, args ...string) (string, error) {
	inprocMu.Lock()
	inprocCalls++
	inprocMu.Unlock()
	src, err := os.ReadFile(programPath)
	if err != nil {
		return "", fmt.Errorf("读取自举前端 %s：%w", programPath, err)
	}
	u, pd := xfront.ParseUnit(programPath, string(src))
	if len(pd) > 0 {
		return "", fmt.Errorf("自举前端 %s 无法解析（%s）", programPath, pd[0].String())
	}
	var out bytes.Buffer
	code, err := interp.Run(u, &out, args)
	if err != nil {
		return "", fmt.Errorf("自举前端运行失败：%w", err)
	}
	if code != 0 {
		return "", fmt.Errorf("自举前端退出码 %d", code)
	}
	return out.String(), nil
}

// ---- 原生 xparser 二进制（生产 auto 路径）----

var (
	nativeOnce sync.Once
	nativeBin  string
	nativeErr  error
)

// nativeParser 返回可用的原生 xparser 二进制。
// 解析顺序：XNULL_NATIVE_XPARSER → 缓存目录中的已构建二进制 → 可选的一次性自动构建。
func nativeParser() (string, error) {
	nativeOnce.Do(func() { nativeBin, nativeErr = resolveNativeParser() })
	return nativeBin, nativeErr
}

func resolveNativeParser() (string, error) {
	if v := strings.TrimSpace(os.Getenv("XNULL_NATIVE_XPARSER")); v != "" {
		if isExecutable(v) {
			return v, nil
		}
		return "", fmt.Errorf("XNULL_NATIVE_XPARSER 不可执行：%s", v)
	}
	parser, err := parserFile("xparser.x", "XNULL_SELFHOST_XPARSER")
	if err != nil {
		return "", err
	}
	hash, err := fileSHA256(parser)
	if err != nil {
		return "", err
	}
	cache, err := cacheDir()
	if err != nil {
		return "", err
	}
	bin := filepath.Join(cache, "native", "xparser-"+hash[:16])
	if isExecutable(bin) {
		return bin, nil
	}
	if !autobuildEnabled() {
		return "", fmt.Errorf("未找到原生 xparser 二进制")
	}
	if markerFresh(bin + ".fail") {
		return "", fmt.Errorf("原生 xparser 构建失败标记仍在有效期内")
	}
	return buildNativeParser(parser, bin, cache)
}

func autobuildEnabled() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("XNULL_FRONTEND_AUTOBUILD"))) {
	case "0", "off", "false", "no":
		return false
	case "1", "on", "true", "yes":
		return true
	}
	// 默认：能找到工具链才尝试，避免每次进程都白跑。
	_, ok := toolchainBin()
	return ok
}

func toolchainBin() (string, bool) {
	if v := strings.TrimSpace(os.Getenv("XNULL_TOOLCHAIN_BIN")); v != "" && isExecutable(v) && !sameExecutable(v) {
		return v, true
	}
	p, err := exec.LookPath("xnull")
	if err != nil || p == "" || sameExecutable(p) {
		return "", false
	}
	return p, true
}

func buildNativeParser(parser, bin, cache string) (string, error) {
	tool, ok := toolchainBin()
	if !ok {
		return "", fmt.Errorf("未找到 xnull 工具链，无法构建原生 xparser")
	}
	if err := os.MkdirAll(filepath.Dir(bin), 0o755); err != nil {
		return "", err
	}
	tmp := bin + fmt.Sprintf(".tmp-%d", os.Getpid())
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, tool, "build", parser, "-o", tmp)
	cmd.Env = append(os.Environ(), innerGuard+"=1", buildGuard+"=1")
	var errb bytes.Buffer
	cmd.Stderr = &errb
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(errb.String())
		if msg == "" {
			msg = err.Error()
		}
		_ = os.WriteFile(bin+".fail", []byte(msg+"\n"), 0o644)
		return "", fmt.Errorf("构建原生 xparser 失败：%s", msg)
	}
	if err := os.Chmod(tmp, 0o755); err != nil {
		return "", err
	}
	if err := os.Rename(tmp, bin); err != nil {
		return "", err
	}
	_ = os.Remove(bin + ".fail")
	return bin, nil
}

func markerFresh(path string) bool {
	st, err := os.Stat(path)
	if err != nil {
		return false
	}
	return time.Since(st.ModTime()) < time.Hour
}

var nativeRunner = runNative

func runNative(bin string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), selfhostTimeout())
	defer cancel()
	cmd := exec.CommandContext(ctx, bin, args...)
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return "", fmt.Errorf("原生 xparser 超时（%s）", selfhostTimeout())
	}
	if err != nil {
		msg := strings.TrimSpace(errb.String())
		if msg == "" {
			return "", fmt.Errorf("原生 xparser 失败：%v", err)
		}
		return "", fmt.Errorf("原生 xparser 失败：%v：%s", err, msg)
	}
	return out.String(), nil
}

// ---- AST 缓存（内容 SHA-256 + 进程内 LRU + 磁盘）----

type lruEntry struct {
	key string
	val string
}

type lruCache struct {
	mu  sync.Mutex
	cap int
	ll  *list.List
	m   map[string]*list.Element
}

func newLRU(cap int) *lruCache {
	return &lruCache{cap: cap, ll: list.New(), m: map[string]*list.Element{}}
}

func (c *lruCache) get(key string) (string, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if el, ok := c.m[key]; ok {
		c.ll.MoveToFront(el)
		return el.Value.(*lruEntry).val, true
	}
	return "", false
}

func (c *lruCache) put(key, val string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if el, ok := c.m[key]; ok {
		el.Value.(*lruEntry).val = val
		c.ll.MoveToFront(el)
		return
	}
	el := c.ll.PushFront(&lruEntry{key: key, val: val})
	c.m[key] = el
	for c.ll.Len() > c.cap {
		last := c.ll.Back()
		if last == nil {
			break
		}
		c.ll.Remove(last)
		delete(c.m, last.Value.(*lruEntry).key)
	}
}

var astCache = newLRU(256)

func cacheKey(parserHash, src string) string {
	h := sha256.New()
	h.Write([]byte(cacheFormat))
	h.Write([]byte{0})
	h.Write([]byte(parserHash))
	h.Write([]byte{0})
	h.Write([]byte(src))
	return hex.EncodeToString(h.Sum(nil))
}

func cacheDir() (string, error) {
	if v := strings.TrimSpace(os.Getenv("XNULL_FRONTBRIDGE_CACHE")); v != "" {
		return v, nil
	}
	d, err := os.UserCacheDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(d, "xnull", "frontbridge"), nil
}

func diskCachePath(key string) (string, bool) {
	dir, err := cacheDir()
	if err != nil {
		return "", false
	}
	return filepath.Join(dir, "ast", key[:2], key+".ast"), true
}

func cacheGet(key string) (string, bool) {
	if v, ok := astCache.get(key); ok {
		return v, true
	}
	p, ok := diskCachePath(key)
	if !ok {
		return "", false
	}
	b, err := os.ReadFile(p)
	if err != nil {
		return "", false
	}
	astCache.put(key, string(b))
	return string(b), true
}

func cachePut(key, val string) {
	astCache.put(key, val)
	p, ok := diskCachePath(key)
	if !ok {
		return
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return
	}
	tmp := p + fmt.Sprintf(".tmp-%d", os.Getpid())
	if err := os.WriteFile(tmp, []byte(val), 0o644); err != nil {
		return
	}
	_ = os.Rename(tmp, p)
}

func parserAST(src, mode string) (string, error) {
	parser, err := parserFile("xparser.x", "XNULL_SELFHOST_XPARSER")
	if err != nil {
		return "", err
	}
	hash, err := fileSHA256(parser)
	if err != nil {
		return "", fmt.Errorf("读取 %s：%w", parser, err)
	}
	key := cacheKey(hash, src)
	if v, ok := cacheGet(key); ok {
		return v, nil
	}
	var out string
	if native, nerr := nativeParser(); nerr == nil {
		out, err = nativeRunner(native, src)
	} else if mode == modeXNull {
		// 显式自举模式才允许解释器（外部优先，进程内兜底）。
		out, err = RunSelfhost(parser, src)
	} else {
		return "", nerr
	}
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(out) == "" {
		return "", fmt.Errorf("XNull 前端无输出")
	}
	cachePut(key, out)
	return out, nil
}

func fileSHA256(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:]), nil
}

func parserFile(name, envKey string) (string, error) {
	if v := strings.TrimSpace(os.Getenv(envKey)); v != "" {
		if st, err := os.Stat(v); err == nil && !st.IsDir() {
			return v, nil
		}
		return "", fmt.Errorf("%s 指向的文件不存在：%s", envKey, v)
	}
	starts := []string{}
	if wd, err := os.Getwd(); err == nil {
		starts = append(starts, wd)
	}
	if exe, err := os.Executable(); err == nil {
		starts = append(starts, filepath.Dir(exe))
	}
	if _, file, _, ok := runtime.Caller(0); ok {
		starts = append(starts, filepath.Dir(file))
	}
	for _, start := range starts {
		dir := start
		for i := 0; i < 10; i++ {
			for _, cand := range []string{
				filepath.Join(dir, "impl", "lib", "b2", name),
				filepath.Join(dir, "lib", "b2", name),
			} {
				if st, err := os.Stat(cand); err == nil && !st.IsDir() {
					return cand, nil
				}
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}
	return "", fmt.Errorf("找不到自举前端 %s（可用 %s 指定）", name, envKey)
}

func isExecutable(path string) bool {
	st, err := os.Stat(path)
	if err != nil || st.IsDir() {
		return false
	}
	return st.Mode()&0o111 != 0
}
