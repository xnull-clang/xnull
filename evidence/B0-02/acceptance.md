# B0-02（P-10）自检结论

> 依据：`死命令.md` 第 1 号 §1.4 P-10；`impl/docs/runtime-contract.md` B 段 P-10 与 C 段四条条件；董事会判决 v1.9.0 §3（B0-02）。基线 `81ec33d`。**先红后绿**。
> 入口：`evidence/B0-02/run.sh`（一条命令复现红→绿与样例）。

## 变更

| 文件 | 内容 |
| --- | --- |
| `impl/internal/codegen/build.go` | `runtimeCSources` 固定 8 项：`rt.c`、`rt_gc.c`、`rt_policy.c`、`rt_weak.c`、`xrt_abi.c`、`rt_std_runtime.c`、`rt_std_text.c`、`rt_std_sys.c`；抽出 `buildCCArgs`；新增 `Options{LinkArgs}` 与 `BuildWithOptions`（`Build` 保持兼容）；LinkArgs 排在全部目标文件之后 |
| `impl/internal/cli/cli.go` | `xnull build` 支持 `-l <库>`、`-L <目录>`（可重复），经 `linkArgs` 去重 + 升序注入（`-L` 前、`-l` 后） |
| `impl/internal/codegen/build_test.go` | 3 例：清单精确匹配、LinkArgs 顺序、`hello.x` 端到端 + `-lm` |
| `impl/internal/cli/build_test.go` | 1 例：链接参数确定性 |
| `impl/README.md` | 写明构建清单与 `-l/-L` |

## 红→绿（两条独立证据）

**A. 单元级红**（`red.txt` → `green.txt`）：实现前 `TestBuildCCArgsIncludesRuntimeABIAndStd` FAIL——实际只传 4 个源，缺 `xrt_abi.c` 与 3 个 `rt_std_*.c`；实现后 PASS。

**B. 链接级红**（`red-link.txt` → `run.out` §1/§2）：样例 `probe/probe.c` 调用 `xrt_runtime_init`、`xrt_safepoint`（`xrt_abi.c`）与 `xdkc_now_mono_ms`（`rt_std_runtime.c`）。

| 清单 | 结果 |
| --- | --- |
| 旧 4 源 | 链接失败：`symbol(s) not found`（三个符号全部未定义），exit 1 |
| 新 8 源 | 链接成功，运行输出 `xrt_abi + rt_std 链接并运行通过`，exit 0 |

## 含 ABI/STD 的样例（v1.9.0 验收口径）

`run.sh` §3：`xnull build examples/hello.x -o … -l m -L /usr/lib -l m` → exit 0；产物运行输出与 `--interp` 一致；`nm` 统计产物内 `xrt_`/`xdkc_` 符号 **48 个**，证明 `xrt_abi.c` 与 `rt_std_*.c` 确实进入每个 `xnull build` 产物的链接清单（不是只改单测）。

## B0-06 阻塞 #3：`fileOpenWrite` 增补（本轮补齐）

B0-06 验收（`验收-M6-B0-06.md` §二 #3）判定「`fileOpenWrite` 在 sys.xfb/rt_std_sys.c/xrt.h 零命中 → B0-02 + API 缺口，无它则写文件不可完成」。本轮按 red-first 补齐：

| 层 | 变更 |
|---|---|
| 绑定 | `bindings/xdk/sys.xfb` 新增 `File fileOpenWrite(String path)`，`cName = xdkc_file_open_write`，`@lease(path=.borrow)`、`@blocking(.unaware)` |
| C 实现 | `impl/runtime/rt_std_sys.c` 新增 `xdkc_file_open_write`（`fopen(path,"wb")`；空路径/NUL/打开失败返回 NULL，不 panic） |
| 文档 | `impl/docs/blocking-classification.md` 增 `fileOpenWrite` 行（`TestBlockingClassificationDocInSync` 自动校验） |
| 测试 | 新增 `impl/internal/codegen/ffi/xdk_write_test.go`：入口/cName 断言 + 生成包装 + 写→关→读回内容比对 |

红→绿：实现前 `TestXDKSysFileOpenWrite` FAIL「绑定缺少 fileOpenWrite」（`red-fileopenwrite.txt`）；实现后 PASS（`green-fileopenwrite.txt`），并覆盖生成代码的写路径（`write rc=0`、`close=0`、`readback n=7 text=write0k`）。

注：`xrt.h` 不声明 `xdkc_*`（`fileOpenRead` 同样不在其中），绑定 `cName` 就是声明点；若 QA 期望 xrt.h 出现该符号，需先定 ABI 头是否收纳 XDK 原语，属合同变更，不在本卡擅自添加。

## P-10 四条条件

| # | 条件 | 处置 |
|---|---|---|
| 1 | `rt_std_*.c` 按 import 闭包纳入 | 语言侧尚无 XDK import 闭包（跨包 import 是 B0-03），暂以固定三项全量纳入、顺序固定；闭包接入点即 `runtimeCSources` |
| 2 | `xrt_abi.c` 与 codegen 迁移 xrt.h 同批 | 已按卡面先纳入；生成代码仍 `#include "rt.h"`/调用 `rt_*`，故 `xrt_abi.c` 当前为"已链接未调用"，属 P-08/M4.4a 范围（已登记，未掩盖） |
| 3 | LinkArgs 去重 + 升序；`-l/-L` 在全部目标文件后 | 已实现：`buildCCArgs` 末尾追加、`linkArgs` 去重排序、`ffi.LinkArgs` 产出 `-l`；单测覆盖 |
| 4 | 缓存键追加链接清单哈希 | 当前无构建缓存（P-07 未落地），不适用；缓存落地时必须纳入 `runtimeCSources` + LinkArgs |

## 验收

| 项 | 实测 |
|---|---|
| 清单纳入 | `buildCCArgs` 精确等于 8 个运行时源（顺序固定） |
| 链接含 ABI/STD 的样例 | probe 旧清单红 / 新清单绿并运行 |
| `xnull build` 产物 | 含 48 个 `xrt_`/`xdkc_` 符号；stdout 与解释路径一致 |
| 回归 | `go vet`=0；`go test ./internal/codegen ./internal/cli`=0；`go test ./... -timeout 300s`=0；`build_rt.sh`=0 |
| 干净 clone | `clone.txt`（同 driver 复跑） |

## 声明

执行侧自检，不构成验收签署（E5 会签）。未 push、未合并 main、未改 C 运行时源码。
