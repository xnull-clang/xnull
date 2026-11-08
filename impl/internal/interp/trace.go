// trace.go：解释执行调用轨迹（诊断用，默认关闭）。
//
// 设置 XNULL_INTERP_TRACE=1 后，解释器把顶层函数/实例方法/静态方法/工厂方法的
// 进入与退出写到 stderr，用来定位无限循环、重复派发和意外的重载选择。
// XNULL_INTERP_TRACE_LINES 可限制输出行数（默认 100000），避免问题程序把日志写爆。
package interp

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

func (in *Interp) initTrace() {
	if strings.TrimSpace(os.Getenv("XNULL_INTERP_TRACE")) == "" {
		return
	}
	in.trace = os.Stderr
	in.traceLimit = 100000
	if n, err := strconv.Atoi(os.Getenv("XNULL_INTERP_TRACE_LINES")); err == nil && n > 0 {
		in.traceLimit = n
	}
}

// traceCall 记录一次调用进入，返回退出回调。关闭时零开销。
func (in *Interp) traceCall(kind, name string, pos xfront.Pos) func() {
	if in.trace == nil {
		return func() {}
	}
	depth := in.traceDepth
	in.traceDepth++
	if in.traceLines < in.traceLimit {
		in.traceLines++
		fmt.Fprintf(in.trace, "interp trace: %s%s %s @%d:%d (depth %d)\n",
			strings.Repeat("  ", depth), kind, name, pos.Line, pos.Col, depth)
		if in.traceLines == in.traceLimit {
			fmt.Fprintf(in.trace, "interp trace: 输出达到上限 %d 行，后续轨迹已关闭\n", in.traceLimit)
		}
	}
	return func() { in.traceDepth-- }
}
