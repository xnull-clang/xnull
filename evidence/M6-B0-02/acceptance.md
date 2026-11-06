# M6-B0-02（P-10）自检结论

> 依据：`死命令.md` 第 1 号 §1.4 P-10；`impl/docs/runtime-contract.md` B 段 P-10 与 C 段四条条件。基线 `81ec33d`。先红后绿。

## 变更

| 文件 | 内容 |
| --- | --- |
| `impl/internal/codegen/build.go` | 新增 `runtimeCSources`（固定顺序 8 项：`rt.c`、`rt_gc.c`、`rt_policy.c`、`rt_weak.c`、`xrt_abi.c`、`rt_std_runtime.c`、`rt_std_text.c`、`rt_std_sys.c`）；抽出 `buildCCArgs`；新增 `Options{LinkArgs}` 与 `BuildWithOptions`（`Build` 保持兼容）；LinkArgs 排在全部目标文件之后 |
| `impl/internal/cli/cli.go` | `xnull build` 支持 `-l <库>`（可重复）与 `-L <目录>`（可重复），经 `linkArgs` 去重 + 升序后注入（`-L` 在前、`-l` 在后） |
| `impl/internal/codegen/build_test.go` | 新增 3 个用例：运行时源清单精确匹配、LinkArgs 必须在目标文件后、`hello.x` 端到端 + `-lm` |
| `impl/internal/cli/build_test.go` | 新增 `TestLinkArgsDeterministic`（去重 + 升序 + `-L` 优先） |
| `impl/README.md` | 写明构建清单与 `-l/-L` 语义 |

## P-10 四条条件

| # | 条件 | 本卡处置 |
|---|---|---|
| 1 | `rt_std_*.c` 按 import 闭包纳入、按 import 书写序 | 语言侧尚无可声明的 XDK import 闭包（跨包 import 属 B0 另一项），故暂以**固定三项全量**纳入、顺序固定；闭包裁剪在 import 机制落地后接入，位置即 `runtimeCSources` |
| 2 | `xrt_abi.c` 与 codegen 迁移 xrt.h 同批 | 本卡按卡面要求先纳入。生成代码目前仍 `#include "rt.h"` 并调用 `rt_*`，`xrt_abi.c` 为**死代码但无害**；与 CTO 建议的"同批切换"存在偏差，已在回执登记，迁移（P-08/M4.4a）落地后自动转为活代码 |
| 3 | LinkArgs 去重 + 升序；`-l/-L` 在全部目标文件之后 | 已实现并有单测：`buildCCArgs` 末尾追加；`linkArgs` 去重排序；`ffi.LinkArgs` 负责 `-l` |
| 4 | 缓存键追加链接清单哈希 | 当前无构建缓存（P-07 未落地），不适用；缓存落地时必须把 `runtimeCSources` + LinkArgs 纳入键 |

## 先红后绿

- 红：`TestBuildCCArgsIncludesRuntimeABIAndStd` FAIL —— 实际参数只有 `rt.c`…`rt_weak.c`，缺 `xrt_abi.c` 与 3 个 `rt_std_*.c`（见 `red.txt`）。
- 绿：同一测试 PASS（`green.txt`）。

## 验收

| 项 | 实测 |
|---|---|
| 清单纳入 | `buildCCArgs` 精确等于 8 个运行时源，顺序固定 |
| LinkArgs | `-lm -lz` 位于全部 `.c` 之后；CLI `-l m -L /usr/lib -l m` → `-L/usr/lib -lm`（去重、升序） |
| 样例 | `xnull build examples/hello.x -o /tmp/m6-hello -l m -L /usr/lib -l m` exit 0；运行输出 `hello, XNull` / `1 + 2 = 3`，与 `--interp` 一致 |
| 回归 | `go vet ./...`=0；`go test ./... -timeout 300s`=0（9 包）；`build_rt.sh`=0 |
| 干净 clone | 见 `clone.txt` |

## 声明

执行侧自检，不构成验收签署。未 push、未合并 main、未改 C 运行时源码。
