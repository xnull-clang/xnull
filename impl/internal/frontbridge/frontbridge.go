package frontbridge

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/interp"
	"xnull.dev/xnull/internal/xfront"
)

// 前端模式（XNULL_FRONTEND）：
//   - auto（默认）：优先 XNull，失败回退 Go；
//   - xnull：只允许 XNull，失败返回桥接诊断；
//   - go：直接使用 Go oracle（旧路径）。
const (
	modeAuto   = "auto"
	modeXNull  = "xnull"
	modeGo     = "go"
	innerGuard = "XNULL_FRONTEND_INNER"
)

// ParseUnit 是 check/run/build 的统一解析入口。
//
// Go xfront 先跑一次，仅用于诊断与回退；正常文件的 AST 来自 XNull 前端。
// 这样错误消息、退出码、诊断顺序与旧路径保持一致，同时 AST 来源已切换。
func ParseUnit(file, src string) (*xfront.CompilationUnit, []diag.Diagnostic) {
	goUnit, goDiags := xfront.ParseUnit(file, src)
	if len(goDiags) > 0 {
		return goUnit, goDiags
	}
	if frontendMode() == modeGo || os.Getenv(innerGuard) != "" {
		return goUnit, nil
	}
	if frontendMode() == modeAuto && len(src) > autoSizeLimit() {
		// 大文件在解释器下成本不可控（xnfmt 基线约 30s）；auto 直接回退，
		// 显式 XNULL_FRONTEND=xnull 时仍强制走自举前端。
		return goUnit, nil
	}
	dump, err := parserAST(src)
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
	if frontendMode() == modeXNull {
		return nil, []diag.Diagnostic{{
			File: file, Line: 1, Col: 1, Code: "B2-001",
			Message: "XNull 前端失败：" + err.Error(),
			Hint:    "设置 XNULL_FRONTEND=go 可回退 Go 前端",
		}}
	}
	// auto：回退 Go AST，行为与旧路径一致。
	return goUnit, nil
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
// 优先外部二进制（XNULL_SELFHOST_BIN / XNULL_BIN），否则走进程内解释器。
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
	inprocOnce sync.Once
	inprocOK   bool
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
	case "", "auto":
		return modeAuto
	case "xnull", "selfhost":
		return modeXNull
	case "go", "oracle":
		return modeGo
	default:
		return modeAuto
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

func autoSizeLimit() int {
	const def = 16 * 1024
	if v := strings.TrimSpace(os.Getenv("XNULL_FRONTEND_MAX_BYTES")); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n
		}
	}
	return def
}

func selfhostTimeout() time.Duration {
	if v := strings.TrimSpace(os.Getenv("XNULL_SELFHOST_TIMEOUT")); v != "" {
		if n, err := time.ParseDuration(v); err == nil && n > 0 {
			return n
		}
	}
	return 120 * time.Second
}

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

// ---- 解析器源码定位与缓存 ----

var (
	parserCacheMu sync.Mutex
	parserCache   = map[string]string{}
)

func parserAST(src string) (string, error) {
	path, err := parserFile("xparser.x", "XNULL_SELFHOST_XPARSER")
	if err != nil {
		return "", err
	}
	psrc, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("读取 %s：%w", path, err)
	}
	h := sha256.New()
	h.Write(psrc)
	h.Write([]byte{0})
	h.Write([]byte(src))
	key := hex.EncodeToString(h.Sum(nil))
	parserCacheMu.Lock()
	if v, ok := parserCache[key]; ok {
		parserCacheMu.Unlock()
		return v, nil
	}
	parserCacheMu.Unlock()
	out, err := RunSelfhost(path, src)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(out) == "" {
		return "", fmt.Errorf("XNull 前端无输出")
	}
	parserCacheMu.Lock()
	if len(parserCache) >= 512 {
		parserCache = map[string]string{}
	}
	parserCache[key] = out
	parserCacheMu.Unlock()
	return out, nil
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
