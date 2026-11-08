package frontbridge

import (
	"bytes"
	"container/list"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/xfront"
)

// 前端模式（XNULL_FRONTEND）：
//   - 未设置（默认）：解释器前端（xnull 管线 + 磁盘缓存）；失败/超时回退 Go；
//   - auto：同默认（显式写法）；
//   - xnull：显式自举；失败返回 B2-001，超时回退 Go 并记 B2-002；
//   - go：直接使用 Go oracle。
//
// B2-04f：E3 修复解释器递归前，默认保持 go；进程内 runner 因无法取消已改为独立进程 + 硬超时。
//
// B2-04b：全量 codegen 未达到 ≤170s 门禁前，默认保持 go；auto 由显式环境变量开启。
const (
	modeDefault = "default"
	modeAuto    = "auto"
	modeXNull   = "xnull"
	modeGo      = "go"
	innerGuard  = "XNULL_FRONTEND_INNER"
	buildGuard  = "XNULL_FRONTEND_BUILDING"

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
// 默认/auto 走“缓存 → 原生 xparser → 解释器”，无 runner 或失败时回退 Go；
// 显式 xnull 才把前端失败升级为 B2-001。
func ParseUnit(file, src string) (*xfront.CompilationUnit, []diag.Diagnostic) {
	goUnit, goDiags := xfront.ParseUnit(file, src)
	if len(goDiags) > 0 {
		return goUnit, goDiags
	}
	mode := frontendMode()
	if mode == modeGo || os.Getenv(innerGuard) != "" || os.Getenv(buildGuard) != "" {
		return goUnit, nil
	}
	// xnull/auto 都先查磁盘缓存；命中时直接反序列化，不启动任何 runner。
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
	if isTimeout(err) {
		// 超时一律回退 Go（含显式 xnull），并记录 B2-002；不阻塞工具链。
		recordIssue("B2-002", "XNull 前端超时："+err.Error())
		return goUnit, nil
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
// 优先外部解释器二进制（XNULL_SELFHOST_BIN / XNULL_BIN），否则使用自动构建并缓存
// 的 xnselfhost helper（独立进程，可被 CommandContext 取消）。
func RunSelfhost(programPath string, args ...string) (string, error) {
	bin := selfhostBin()
	if bin != "" && !sameExecutable(bin) {
		return runExternal(bin, programPath, args...)
	}
	if helperBroken.Load() {
		return "", fmt.Errorf("xnselfhost helper 不可用（进程级缓存）")
	}
	helper, err := selfhostHelper()
	if err != nil {
		return "", err
	}
	out, err := runHelper(helper, programPath, args...)
	if err != nil && !isTimeout(err) {
		helperBroken.Store(true)
	}
	return out, err
}

const helperVersion = "b2-04g-1"

var (
	helperOnce   sync.Once
	helperBin    string
	helperErr    error
	helperBroken atomic.Bool
)

func selfhostHelper() (string, error) {
	helperOnce.Do(func() { helperBin, helperErr = resolveHelper() })
	return helperBin, helperErr
}

func resolveHelper() (string, error) {
	if v := strings.TrimSpace(os.Getenv("XNULL_SELFHOST_HELPER")); v != "" {
		if isExecutable(v) {
			return v, nil
		}
		return "", fmt.Errorf("XNULL_SELFHOST_HELPER 不可执行：%s", v)
	}
	root, err := moduleRoot()
	if err != nil {
		return "", err
	}
	hash, err := helperHash(root)
	if err != nil {
		return "", err
	}
	cache, err := cacheDir()
	if err != nil {
		return "", err
	}
	bin := filepath.Join(cache, "helper", "xnselfhost-"+hash[:16])
	if isExecutable(bin) {
		return bin, nil
	}
	return buildHelper(root, bin)
}

// moduleRoot 从本文件向上找到包含 go.mod 与 cmd/xnselfhost 的 impl 模块根。
func moduleRoot() (string, error) {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		return "", fmt.Errorf("无法定位 frontbridge 源码路径")
	}
	dir := filepath.Dir(file)
	for i := 0; i < 8; i++ {
		if st, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil && !st.IsDir() {
			if st, err := os.Stat(filepath.Join(dir, "cmd", "xnselfhost", "main.go")); err == nil && !st.IsDir() {
				return dir, nil
			}
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "", fmt.Errorf("找不到 impl 模块根（cmd/xnselfhost）")
}

func helperHash(root string) (string, error) {
	h := sha256.New()
	h.Write([]byte(helperVersion))
	h.Write([]byte{0})
	for _, rel := range []string{"go.mod", "cmd/xnselfhost/main.go"} {
		b, err := os.ReadFile(filepath.Join(root, rel))
		if err != nil {
			return "", err
		}
		h.Write(b)
		h.Write([]byte{0})
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func buildHelper(root, bin string) (string, error) {
	if err := os.MkdirAll(filepath.Dir(bin), 0o755); err != nil {
		return "", err
	}
	tmp := bin + fmt.Sprintf(".tmp-%d", os.Getpid())
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "go", "build", "-o", tmp, "./cmd/xnselfhost")
	cmd.Dir = root
	cmd.Env = append(os.Environ(), innerGuard+"=1", buildGuard+"=1")
	var errb bytes.Buffer
	cmd.Stderr = &errb
	if err := cmd.Run(); err != nil {
		_ = os.Remove(tmp)
		msg := strings.TrimSpace(errb.String())
		if msg == "" {
			msg = err.Error()
		}
		return "", fmt.Errorf("构建 xnselfhost helper 失败：%s", msg)
	}
	if err := os.Chmod(tmp, 0o755); err != nil {
		return "", err
	}
	if err := os.Rename(tmp, bin); err != nil {
		return "", err
	}
	return bin, nil
}

func runHelper(bin, programPath string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), selfhostTimeout())
	defer cancel()
	cmdArgs := append([]string{programPath}, args...)
	cmd := exec.CommandContext(ctx, bin, cmdArgs...)
	cmd.Env = append(os.Environ(), innerGuard+"=1")
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return "", timeoutError{selfhostTimeout()}
	}
	if err != nil {
		msg := strings.TrimSpace(errb.String())
		if msg == "" {
			return "", fmt.Errorf("自举前端失败：%v", err)
		}
		return "", fmt.Errorf("自举前端失败：%v：%s", err, msg)
	}
	return out.String(), nil
}

var lastIssue atomic.Value // string：最近一次前端问题（B2-002 等），供测试/诊断读取。

// LastIssue 返回最近一次前端问题（形如 "B2-002: ..."）；无问题为空串。
func LastIssue() string {
	v, _ := lastIssue.Load().(string)
	return v
}

func recordIssue(code, msg string) { lastIssue.Store(code + ": " + msg) }

// timeoutError 表示前端执行超时。
type timeoutError struct{ d time.Duration }

func (e timeoutError) Error() string { return "超时（" + e.d.String() + "）" }

func isTimeout(err error) bool {
	var te timeoutError
	return errors.As(err, &te)
}

// explicitNative 只认显式 XNULL_NATIVE_XPARSER；原生 parser 暂缓，不参与默认发现/自动构建。
func explicitNative() (string, bool) {
	v := strings.TrimSpace(os.Getenv("XNULL_NATIVE_XPARSER"))
	if v != "" && isExecutable(v) {
		return v, true
	}
	return "", false
}

func frontendMode() string {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("XNULL_FRONTEND"))) {
	case "":
		return modeDefault
	case "go", "oracle":
		return modeGo
	case "auto":
		return modeAuto
	case "xnull", "selfhost":
		return modeXNull
	default:
		return modeDefault
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
	return 5 * time.Second
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
		return "", timeoutError{selfhostTimeout()}
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
	// 默认不自动构建（原生 parser 暂缓）；仅显式开启。
	return false
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
		return "", timeoutError{selfhostTimeout()}
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
	if native, ok := explicitNative(); ok {
		out, err = nativeRunner(native, src)
	} else if mode == modeAuto || mode == modeXNull || mode == modeDefault {
		// 解释器前端：外部二进制优先，进程内兜底；默认/auto 失败后回退 Go。
		out, err = RunSelfhost(parser, src)
	} else {
		return "", fmt.Errorf("没有可用前端执行器")
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
