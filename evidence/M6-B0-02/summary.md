# M6-B0-02（P-10）摘要

## 一句话

`xnull build` 的 C 编译清单从 4 个运行时源扩到 8 个（新增 `xrt_abi.c` 与 `rt_std_runtime.c`/`rt_std_text.c`/`rt_std_sys.c`），并打通 `LinkArgs` 注入：`-l/-L` 去重、升序、排在全部目标文件之后。先红后绿。

## 数据

| 项 | 值 |
| --- | --- |
| 基线 | `81ec33d` |
| 红 | 1 个用例 FAIL（缺 4 个源） |
| 绿 | 3 个 codegen 用例 + 1 个 cli 用例 PASS |
| 样例 | `hello.x` + `-lm`，exit 0，输出与解释路径一致 |
| `go test ./...` | 0（9 包） |
| `build_rt.sh` | 0 |
| 干净 clone | 见 `clone.txt` |

## 设计

- `runtimeCSources` 是唯一事实源，顺序固定（确定性）；`buildCCArgs` 只做组装，便于单测。
- `Options.LinkArgs` 是清单接入点：现在由 CLI `-l/-L` 提供，将来 `link.libraries` 解析后复用同一字段。
- `Build` 保留旧签名，调用方零改动。

## 未覆盖 / 风险

1. `rt_std_*.c` 尚未按 import 闭包裁剪（P-10 条件 1）：多链接两个文件，产物略大，但确定性满足。
2. 生成代码仍 `#include "rt.h"` 且调用 `rt_*`，`xrt_abi.c` 暂为死代码（P-10 条件 2 的"同批切换"未完成，属 P-08 迁移范围）。
3. 无构建缓存（P-07 未落地），条件 4 不适用。
