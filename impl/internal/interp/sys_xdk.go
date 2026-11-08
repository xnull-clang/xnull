// sys_xdk.go：K-07 xdk.sys 解释器桥（文件输入通道）。
package interp

import (
	"fmt"
	"os"
	"unicode/utf8"

	"xnull.dev/xnull/internal/xfront"
)

const maxReadFileText = 64 << 20 // 64 MiB，满足 K-07 ≥16 MiB

// evalSysBuiltin 处理 xdk.sys 的同名内建（当前：readFileText）。
// 失败返回明确 runtimeErr（不静默空串）；成功返回 String。
func (in *Interp) evalSysBuiltin(name string, n *xfront.Call, sc *scope) (*Value, bool) {
	if name != "readFileText" {
		return nil, false
	}
	if len(n.Args) != 1 {
		panic(runtimeErr{"readFileText 恰好接受 1 个参数（K-07）"})
	}
	v := in.eval(n.Args[0], sc)
	if v.K != vStr {
		panic(runtimeErr{"readFileText 的参数必须是 String（K-07）"})
	}
	data, err := os.ReadFile(v.S)
	if err != nil {
		panic(runtimeErr{fmt.Sprintf("readFileText: 无法读取文件 %q：%v", v.S, err)})
	}
	if len(data) > maxReadFileText {
		panic(runtimeErr{fmt.Sprintf("readFileText: 文件超过 64 MiB 上限（%d 字节）：%s", len(data), v.S)})
	}
	if !utf8.Valid(data) {
		panic(runtimeErr{fmt.Sprintf("readFileText: 文件不是合法 UTF-8：%s", v.S)})
	}
	return &Value{K: vStr, S: string(data)}, true
}
