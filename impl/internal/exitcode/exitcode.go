// Package exitcode 定义工具链退出码（S9 §5.1）。
package exitcode

// 工具链自身退出码；与运行期程序退出码（S4 §7.2）互不影响。
const (
	Success     = 0   // 全部阶段成功
	BuildFail   = 1   // 构建失败：编译/测试/插件/校验不通过
	Usage       = 2   // 清单或用法错误：词法/文法/未知段落/参数拼写
	Interrupted = 130 // 被中断（收到 SIGINT）
)
