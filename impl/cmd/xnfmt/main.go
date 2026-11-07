// Command xnfmt 是 B1-01 的 Go 版格式化器（oracle）。
//
// 用法：
//
//	xnfmt <file>...           就地格式化（原子批处理：任一失败不写任何文件）
//	xnfmt --check <file>...   只检查：全规范 0，有差异 1，错误 2
//
// 退出码：0 成功；1 仅 --check 有差异；2 用法/编码/词法/IO 错误（R13.4）。
package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"

	"xnull.dev/xnull/internal/xnfmt"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	check := false
	var files []string
	for _, a := range args {
		switch a {
		case "--check":
			check = true
		case "-h", "--help":
			fmt.Fprint(stdout, usage)
			return 0
		default:
			files = append(files, a)
		}
	}
	if len(files) == 0 {
		fmt.Fprintf(stderr, "xnfmt: 缺少文件参数（FMT-104）\n\n%s", usage)
		return 2
	}
	for _, f := range files {
		if st, err := os.Stat(f); err != nil || st.IsDir() {
			fmt.Fprintf(stderr, "xnfmt: %s:0:0: error[FMT-104]: 参数不是可读文件\n", f)
			return 2
		}
	}

	// 先全部读入并格式化（R13.1 原子批处理）。
	type job struct {
		path      string
		orig      []byte
		formatted string
		mode      os.FileMode
	}
	jobs := make([]job, 0, len(files))
	for _, f := range files {
		info, err := os.Stat(f)
		if err != nil {
			fmt.Fprintf(stderr, "xnfmt: %s:0:0: error[FMT-103]: %v\n", f, err)
			return 2
		}
		orig, err := os.ReadFile(f)
		if err != nil {
			fmt.Fprintf(stderr, "xnfmt: %s:0:0: error[FMT-103]: %v\n", f, err)
			return 2
		}
		out, diags := xnfmt.Format(f, string(orig))
		if len(diags) > 0 {
			for _, d := range diags {
				fmt.Fprintln(stderr, d.Error())
			}
			return 2
		}
		jobs = append(jobs, job{path: f, orig: orig, formatted: out, mode: info.Mode()})
	}

	changed := 0
	for _, j := range jobs {
		if string(j.orig) == j.formatted {
			continue
		}
		changed++
		if check {
			continue
		}
		if err := writeAtomic(j.path, j.formatted, j.mode); err != nil {
			fmt.Fprintf(stderr, "xnfmt: %s:0:0: error[FMT-103]: %v\n", j.path, err)
			return 2
		}
	}
	if check && changed > 0 {
		return 1
	}
	return 0
}

// writeAtomic 写同目录临时文件后 rename（R13.2）；保留权限位。
func writeAtomic(path, content string, mode os.FileMode) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, ".xnfmt-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.WriteString(content); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmpName, mode.Perm()); err != nil {
		return err
	}
	return os.Rename(tmpName, path)
}

const usage = `用法：
  xnfmt <file>...           就地格式化
  xnfmt --check <file>...   只检查（0 全规范 / 1 有差异 / 2 错误）
`
