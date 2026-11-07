# CEO2-PJ-首轮：二司运行时域任务拆卡 v1.0.0

> **角色：CEO2-PJ-项目（二司·运行时）**　**日期：2026-11-07**　**性质：只读盘点 + 拆卡**
> **依据：董事会判决 v1.6.0 第 2.2 条（PJ 职责=拆卡/排期/证据完整性）、第 4 条（WIP/worktree/门禁）、第 5 条（首轮只读）；任务卡标准见《董事会任务执行报告 v1.0.0》§3**
> **写入域：`收件箱/CEO2/CEO2PJ-首轮.md`（仅此一个文件）**
> **基线：`main @ dfcf033`；二司 worktree `wt/c2-rd1/2/3 @ dfcf033`（分支 `pod/c2-rd1/2/3`，工作区 0 脏）；S0-28 交付 `81ec33d`，CEO1 未验、未合 main**
> **边界：未改生产代码、未 commit、未 push、未派工、未碰他人文件。**

---

## 0. 结论先行

1. 本轮拆 **15 张卡**，全部 ≤2 人日，单一主责、必签不同人：S3 内存 5 张、S5 并发 4 张、S7 FFI 6 张。
2. **现在只有 3 张能开工**（R0，只读/文档/证据设计）：`S3-00`、`S5-00`、`S7-00`；5 张待 S0-28 验收与 CEO1 放行（R1）；7 张待阶段门（R2）。
3. 二司的瓶颈不是“缺实现”，是**缺可执行证据**：S5 12 项验收在 `status.tsv` 只有 `BLOCK-01` 一行；S3 11 项按台账全部未实现；S7 的 7 项为 2 PASS / 5 部分。
4. FFI 子系统内部可用、用户路径为 0：`codegen` 无 `FFICall` 钩子，`build.go` 只链 `rt.c/rt_gc.c/rt_policy.c/rt_weak.c`，生成 `main` 不调 `xrt_runtime_init`。这是 S7 的前置阻塞，不是 FFI 包本身的缺陷。
5. **发现一处阶段依赖顺序冲突**：`MEM-09`（任务 env external root）属 Stage 3，但必须有 Stage 5 的任务模型才能验收；阶段图存在实质回边 `S3 → S5 → S3`，需董事会裁决（见 §7 `PJ-2`）。
6. §7 的 15 项阻塞未清前（PM `D-1—D-7`、RD3 `B1—B5`、阶段门 1 项、PJ 新发现 2 项），不得签任何“S3/S5/S7 条款闭包”。

---

## 1. 口径与约束

### 1.1 事实基线（本轮实测）

| 项 | 事实 | 来源 |
|---|---|---|
| 主仓 | `dfcf033`（S1-22 改名）；工作区有他人未提交改动（`日志/`、`收件箱/` 等） | `git log` / `git status` |
| 二司 worktree | `wt/c2-rd1/2/3` 均 `dfcf033`，0 脏 | `git -C wt/c2-rdN status --porcelain` |
| S0-28 | 9 个研发 worktree 已建，提交 `81ec33d`；证据只在 `wt/e6-toolchain/evidence/S0-28/`，**根目录无 `evidence/S0-28/`** | 实测 |
| C 运行时 | `build_rt.sh` **exit 0**：rt / gc / hard / abi / std / 资源表六段全过 | 本轮实跑 |
| Go 测试 | `interp/sema/xfront/ffi/devtool/xpd` 全绿；`ffi` 149.1s、`codegen` 137.3s | 本轮实跑 |
| S5 代码 | `impl/` 内无调度器、无 `Context`、无 `Channel`、无 `Mutex` | `grep` |
| FFI 接线 | `codegen` 无 `FFICall/EmitCall`；`build.go:44-48` 无 `xrt_abi.c`/`rt_std_*.c` | 实测 |
| ABI 面 | 生成代码 `#include "rt.h"` + `rt_*`；`main` 只调 `rt_quarantine_flush()`，不调 `xrt_runtime_init` | `codegen.go:26-31`、`:308-310` |
| 台账 | `status.tsv` 36 行；S5 相关仅 `BLOCK-01`；S3 的 MEM-03—13 全部“未实现” | `impl/docs/conformance/status.tsv` |

> 测试时长观察（不单独立卡）：`ffi` 149.1s、`codegen` 137.3s；若 CI 沿用 120s 硬超时会误杀。归三司 CI 处置。

### 1.2 卡号与就绪级

卡号沿用 `S<阶段>-<序号>`；`S3/S5/S7` 分别对应阶段 3/5/7，与 PM 的条款定位 ID `PM-S3-xx` **不是同一命名空间**，不得互引为锚点。

| 就绪级 | 含义 | 允许动作 | 当前卡 |
|---|---|---|---|
| **R0** | 立即可做 | 只读、文档、证据设计；不写生产代码、不改 `status.tsv`、不标 PASS | S3-00、S5-00、S7-00 |
| **R1** | S0-28 验收 + worktree `merge main --ff-only` 后 | 写测试/夹具、做合规收口（不新增语言能力）；跨阶段例外需 CEO1 书面放行 | S3-04、S7-01、S7-02、S7-03、S7-04 |
| **R2** | 对应阶段门通过后 | 写生产代码实现能力 | S3-01、S3-02、S3-03、S5-01、S5-02、S5-03、S7-05 |

阶段门对应关系：S3 ← Stage 2 门；S5 ← Stage 4 门；S7 ← Stage 3 + Stage 4 门。R2 卡在门未过前**只允许做设计评审，不得落代码**。

### 1.3 WIP

按 v1.6.0 §4.2：研发 1 卡/人、QA 1 卡/人、PM/PJ 2 卡/人。**待验仍占 WIP**；超限不接卡，不口头预留。

### 1.4 证据规范（每卡强制）

根目录 `evidence/<卡号>/` 六件套，缺一不算交付：

```
summary.md        一句话 + 变更表 + 结果表
command.txt       可复制命令块
exit_code.txt     每条命令退出码
stdout.txt        标准输出
stderr.txt        标准错误
sha.txt           base sha + 交付 sha
artifact.sha256   产物哈希（二进制/生成物）
```

回执落 `收件箱/CEO2/回执-<卡号>-<主责>.md`，五行：改了什么 / 怎么验 / sha / 产物 / 未测项。

**禁止只把证据留在 worktree**（S0-28 已踩：`wt/e6-toolchain/evidence/` 存在、根目录缺失，导致跨角色取件困难）。

### 1.5 拆卡硬规则

1. 单卡 ≤2 人日；超过必须再拆，不接受“2 人日含缓冲”。
2. 一卡一主责、一必签，且不得同一人。
3. 文件清单写死；同文件同一时刻只有一个写者；增援只做子卡。
4. 依赖只能指向前置卡或阶段门；写权协调（同域主责确认、跨司放行）不算依赖，但必须有书面记录，口头不算。
5. 验收命令必须可复制、可单跑、失败给明确诊断；禁止 `t.Skip` 兜底。
6. 实现者不自验；未落地项不得标 PASS。

---

## 2. 卡片总表（15 张）

| ID | 标题 | 主责 | 必签 | 人日 | 就绪 | 依赖 | 主产物 |
|---|---|---|---|---:|---|---|---|
| **S3-00** | 内存域取证手段评估与并发热点定级 | RD2 | QA1 | 1.0 | R0 | — | 取证评估报告 |
| **S5-00** | S5 12 项验收矩阵补行与用例设计 | QA1 | QA2 | 1.5 | R0 | — | 矩阵提案 + `status.tsv` 补丁 |
| **S7-00** | ABI 收口与 FFI 调用链接线决策包 | RD3 | RD2 | 1.0 | R0 | — | 六偏差处置方案 |
| **S7-01** | `xrt` 稳定 ABI 收口：init 顺序 + barrier/safepoint 语义 | RD2 | QA1 | 2.0 | R1 | S7-00 | `xrt.h`/`xrt_abi.c` + 测试 |
| **S7-02** | codegen 迁 `xrt_*` + `FFICall` 钩子【跨司】 | CEO1-RD3 | CEO1-QA1（ABI 会签 RD2） | 2.0 | R1 | S7-01 + CEO1 放行 | codegen 接线 |
| **S7-03** | 构建清单纳入 `xrt_abi.c` / `rt_std_*.c` + LinkArgs【跨司】 | CEO1-RD3 | CEO1-QA1（会签 RD2） | 1.0 | R1 | S7-02（同批） | `build.go` + `nm` 证据 |
| **S3-01** | 混合图压力 + 终结链顺序（MEM-03/08） | RD2 | QA1 | 2.0 | R2 | S3-00 | `test_mixed.c` |
| **S3-02** | 弱表并发清除（MEM-04） | RD2 | QA2 | 1.5 | R2 | S3-01 | `rt_weak.c` + 压力用例 |
| **S3-03** | 任务作用域 external root（MEM-09） | RD2 | QA1 | 1.5 | R2 | S5-02 + PJ-2 裁决 | `xrt_task_root_*` 语义 |
| **S3-04** | 解释器对 S3/S5 能力的显式拒绝面 | RD1 | QA1 | 1.0 | R1 | —（写权：E3 确认） | 负例 + 诊断 |
| **S5-01** | `Context` + 取消位 + deadline | RD3 | QA2 | 1.5 | R2 | S5-00 | `rt_task.{h,c}` 第一段 |
| **S5-02** | `TaskGroup` 单线程执行器 + `join`/`close` | RD3 | QA2 | 2.0 | R2 | S5-01 | 组/任务最小闭环 |
| **S5-03** | 取消传播 + 清理路径 + `joinDeadline` | RD3 | QA2 | 2.0 | R2 | S5-02 | 取消/超时用例 |
| **S7-04** | 布局矩阵全表 + 未知错误码负例（FFI-02/01） | QA1 | QA2 | 1.5 | R1 | S7-01 | `layout_matrix_test.go` |
| **S7-05** | trampoline 根登记/注销（FFI-05） | RD3 | QA1 | 2.0 | R2 | S7-01 + S3-03 | `EmitTrampoline` + 测试 |

**合计 23.5 人日**（二司自身 20.5；跨司 3.0）。上限 2.0，下限 1.0。

---

## 3. 卡片详情

### S3-00　内存域取证手段评估与并发热点定级

| 项 | 内容 |
|---|---|
| 主责 / 必签 | RD2 / QA1 |
| 人日 / 就绪 / 依赖 | 1.0 / R0 / — |
| 输入 | S3 §7/§8/§11/§12/§13/§16/§25；RD3 首轮 §1.2、§3.3、§4；`rt_gc.c`、`rt_weak.c`、`xrt_abi.c` |
| 文件清单（唯一写者） | 只读；写 `收件箱/CEO2/证据-S3-00-取证评估.md` + `evidence/S3-00/**` |
| 产出 | ① 并发热点表（`g_roots`、GC 链表、隔离区、弱表、句柄 `closed`）；② 每个热点给 `文件:行号`；③ ASan 失效（本机 SIGILL）下的替代手段与实测结果（TSan/helgrind/单线程压力+计数断言，至少 2 种有命令与结论）；④ MEM-03/04/08/09/12 逐条“可取证/不可取证”判定 |
| 验收 | `cd impl/runtime && ./build_rt.sh` exit 0；报告中 5 条 MEM 全部有判定；每个热点有行号；替代手段有命令与退出码 |
| 证据 | `evidence/S3-00/` 六件套 + 上述报告 |
| 边界 | 不改 runtime 代码；不裁技术方案（只列选项与代价）；不写测试代码 |

### S5-00　S5 12 项验收矩阵补行与用例设计

| 项 | 内容 |
|---|---|
| 主责 / 必签 | QA1 / QA2 |
| 人日 / 就绪 / 依赖 | 1.5 / R0 / — |
| 输入 | S5 §10 全 12 项；`status.tsv`；PM `PM-S5-01—07`；RD3 `G1/G2` |
| 文件清单（唯一写者） | 只读 `status.tsv`；写 `收件箱/CEO2/S5-验收矩阵提案.md` + `evidence/S5-00/status-s5.patch`（**补丁文件，不应用到 `status.tsv`**） |
| 产出 | 12 项逐项：锚点 / 断言 / 正例 / 负例 / 压力 / 测试文件名 / 失败诊断 / 单跑命令；`CANCEL-01/02`、`TIMEOUT-01` 三行补行方案 |
| 验收 | 12/12 有行；每项至少 1 正 1 负；每项给出可单跑命令；`cd /Users/vjs/Desktop/XNull-Lang && git apply --check evidence/S5-00/status-s5.patch` 通过 |
| 证据 | `evidence/S5-00/{summary.md,matrix.md,status-s5.patch,command.txt,exit_code.txt}` |
| 边界 | 不改 `status.tsv`（归董事会/CEO3）；不写测试代码；不标 PASS；S5 无实现不是本卡缺陷 |

### S7-00　ABI 收口与 FFI 调用链接线决策包

| 项 | 内容 |
|---|---|
| 主责 / 必签 | RD3 / RD2 |
| 人日 / 就绪 / 依赖 | 1.0 / R0 / — |
| 输入 | S3 §22；S7 §6/§9；P-08/P-09/P-10；`impl/docs/runtime-contract.md`、`ffi-contract.md`；`codegen.go:26-31/308-310`；`build.go:44-48` |
| 文件清单（唯一写者） | 只读；写 `收件箱/CEO2/证据-S7-00-ABI收口方案.md` + `evidence/S7-00/**` |
| 产出 | A1—A6 六偏差逐项：改哪个文件、谁写、同批/分批、回滚点；`rt_*` 到 `xrt_*` 的迁移清单与顺序；明确“禁止中间态双面链接”的合批条件；`nm` 验证方案；跨司子卡 2a/2b/2c 的文件级写权建议 |
| 验收 | 六偏差 6/6 有处置；迁移清单可 `grep` 复核；合批条件写明；`nm` 方案可执行 |
| 证据 | `evidence/S7-00/` 六件套 + 上述方案 |
| 边界 | 不改 codegen/runtime；不派工；跨司写权只建议不裁定 |

### S7-01　`xrt` 稳定 ABI 收口：init 顺序 + barrier/safepoint 语义

| 项 | 内容 |
|---|---|
| 主责 / 必签 | RD2 / QA1 |
| 人日 / 就绪 / 依赖 | 2.0 / R1 / S7-00 |
| 输入 | S7 §6.1/§6.3；S3 §12/§13/§22；`xrt.h`、`xrt_abi.c`、`test_abi.c` |
| 文件清单（唯一写者） | `impl/runtime/xrt.h`、`impl/runtime/xrt_abi.c`、`impl/runtime/test_abi.c` |
| 产出 | ① `xrt_runtime_init` 幂等 + 未初始化违约检测；② `xrt_write_barrier` 保持“存活校验”并显式标注非完整屏障，不谎称已实现；③ `xrt_safepoint` 语义与缺口写明；④ 新增“未 init 创建对象”负例 |
| 验收 | `cd impl/runtime && cc -std=c11 -Wall -Wextra -Werror -O2 -I. -o /tmp/xn_test_abi test_abi.c rt.c rt_gc.c rt_weak.c xrt_abi.c && /tmp/xn_test_abi` exit 0；`./build_rt.sh` exit 0；`nm -g /tmp/xn_test_abi \| grep xrt_runtime_init` 命中；负例给明确诊断 |
| 证据 | `evidence/S7-01/{summary.md,command.txt,exit_code.txt,stdout.txt,stderr.txt,sha.txt,nm.txt}` |
| 边界 | 不接 codegen（S7-02）；不实现完整 GC 写屏障（模型由 S3-01 定）；不改 `rt_*` 内部 ABI |

### S7-02　codegen 迁 `xrt_*` + `FFICall` 钩子【跨司】

| 项 | 内容 |
|---|---|
| 主责 / 必签 | **CEO1-RD3** / CEO1-QA1（ABI 会签 CEO2-RD2） |
| 人日 / 就绪 / 依赖 | 2.0 / R1 / S7-01 + CEO1 书面放行 |
| 输入 | S7 §6；S3 §22；`ffi/emit.go` 的 `EmitCall`/`EmitSupport`；`codegen.go` |
| 文件清单（唯一写者） | `impl/internal/codegen/**`（非 `ffi/`，一司写权）；`impl/internal/codegen/ffi/**` 只读 |
| 产出 | ① 生成代码 `#include "xrt.h"` + `xrt_*`；② 生成 `main` 调 `xrt_runtime_init()`；③ `FFICall` 钩子接 `ffi.Load/EmitCall`；④ 错误码→`Result` 映射；⑤ `examples/ffi-hello.x` 用户路径示例 |
| 验收 | `cd impl && go test ./internal/codegen/ ./internal/codegen/ffi/ -count=1` 全绿；`cd impl && go build -o /tmp/xnull ./cmd/xnull` 成功；产物 `nm` 含 `xrt_*`；负例“未知码→`Internal` 不得 `Ok`” |
| 证据 | `evidence/S7-02/{summary.md,command.txt,exit_code.txt,stdout.txt,stderr.txt,sha.txt,nm.txt}` |
| 边界 | 一次性切完，禁止中间态双面链接；不改 `ffi/` 包内部；示例入库需 COO/一司门 |

### S7-03　构建清单纳入 `xrt_abi.c` / `rt_std_*.c` + LinkArgs【跨司】

| 项 | 内容 |
|---|---|
| 主责 / 必签 | **CEO1-RD3** / CEO1-QA1（会签 CEO2-RD2） |
| 人日 / 就绪 / 依赖 | 1.0 / R1 / S7-02（同批合入） |
| 输入 | P-10 四条条件；`build.go:44-48`；`ffi.LinkArgs` |
| 文件清单（唯一写者） | `impl/internal/codegen/build.go` |
| 产出 | ① cc 清单按 import 闭包加入 `xrt_abi.c` + `rt_std_*.c`；② `LinkArgs` 去重升序；③ 缓存键含闭包；④ 与 S7-02 同批合入 |
| 验收 | `cd impl && go test ./internal/codegen/ -count=1` 全绿；`grep -n "xrt_abi.c\|rt_std_" impl/internal/codegen/build.go` 命中；构建产物 `nm` 含 ABI 符号；两次构建产物逐字节一致 |
| 证据 | `evidence/S7-03/{summary.md,command.txt,exit_code.txt,nm.txt,sha.txt,artifact.sha256}` |
| 边界 | 不与 S7-02 分开合入；不动 `ci/**` |

### S3-01　混合图压力 + 终结链顺序（MEM-03 / MEM-08）

| 项 | 内容 |
|---|---|
| 主责 / 必签 | RD2 / QA1 |
| 人日 / 就绪 / 依赖 | 2.0 / R2（Stage 2 门）/ S3-00 |
| 输入 | S3 §14/§15；S2 §15.6 六条不变量；`test_gc.c`、`test_hard.c` |
| 文件清单（唯一写者） | `impl/runtime/test_gc.c`、`impl/runtime/test_hard.c`、新增 `impl/runtime/test_mixed.c` |
| 产出 | ① 混合图压力（ARC↔GC 互引、环、弱边、容器）连续 N 轮；② 分配/释放计数差归零；③ ARC 终结五步与 GC 清扫顺序可观测；④ 复活终止进程用例；⑤ 故障注入（故意漏 release）能红 |
| 验收 | `cd impl/runtime && cc -std=c11 -Wall -Wextra -Werror -O2 -o /tmp/xn_test_mixed test_mixed.c rt.c rt_gc.c rt_weak.c && /tmp/xn_test_mixed` exit 0；`./build_rt.sh` exit 0；每轮计数断言；故障注入用例失败 |
| 证据 | `evidence/S3-01/{summary.md,command.txt,exit_code.txt,stdout.txt,stderr.txt,sha.txt}` |
| 边界 | 不改 `rt.c` 语义；必要修复另开子卡；GC 时机不承诺；同周期多对象 `deinit` 顺序不承诺 |

### S3-02　弱表并发清除（MEM-04）

| 项 | 内容 |
|---|---|
| 主责 / 必签 | RD2 / QA2 |
| 人日 / 就绪 / 依赖 | 1.5 / R2（Stage 2 门）/ S3-01 |
| 输入 | S3 §7/§16；`rt_weak.c`；S3-00 结论 |
| 文件清单（唯一写者） | `impl/runtime/rt_weak.c`、`impl/runtime/test_hard.c`（或新增 `test_weak_mt.c`） |
| 产出 | ① 弱表操作原子化，或显式单线程约束 + 运行时断言；② 目标进终结链前清槽；③ 并发清/读不观察到已终结目标的证据；④ 槽位复用 |
| 验收 | `cd impl/runtime && ./build_rt.sh` exit 0；新增压力用例可单跑；已清除返回 `NULL`；若并发不可取证，给“单线程模型 + 断言”降级证据并标注不可签项 |
| 证据 | `evidence/S3-02/{summary.md,command.txt,exit_code.txt,stdout.txt,stderr.txt,sha.txt}` |
| 边界 | 不暴露公共 API；不承诺竞争检测；不得用“跑了没崩”当证据 |

### S3-03　任务作用域 external root（MEM-09）

| 项 | 内容 |
|---|---|
| 主责 / 必签 | RD2 / QA1 |
| 人日 / 就绪 / 依赖 | 1.5 / R2（Stage 3 门）/ S5-02 + `PJ-2` 裁决 |
| 输入 | S3 §11.1；S5 §4.4；`xrt_abi.c:77-79`；S5-02 冻结的任务句柄 |
| 文件清单（唯一写者） | `impl/runtime/xrt_abi.c`、`impl/runtime/xrt.h`；**不改 `rt_task.*`** |
| 产出 | ① `xrt_task_root_bind/unbind` 改为任务作用域（不再等于进程级 root）；② 任务存活期间 env 可达；③ 终结后解除并可回收；④ 重复 unbind 安全 |
| 验收 | `cd impl/runtime && cc -std=c11 -Wall -Wextra -Werror -O2 -o /tmp/xn_test_root test_task_root.c rt.c rt_gc.c rt_weak.c xrt_abi.c && /tmp/xn_test_root` exit 0；GC 压力断言：存活可达 / 终结可回收 |
| 证据 | `evidence/S3-03/{summary.md,command.txt,exit_code.txt,stdout.txt,stderr.txt,sha.txt}` |
| 边界 | 依赖 S5-02 的任务句柄；不改调度器；阶段归属待 `PJ-2` 裁决 |

### S3-04　解释器对 S3/S5 能力的显式拒绝面

| 项 | 内容 |
|---|---|
| 主责 / 必签 | RD1 / QA1 |
| 人日 / 就绪 / 依赖 | 1.0 / R1 / —（写权协调：E3 书面确认无在途） |
| 输入 | S5 §9（未实现前不得声称支持）；`impl/README.md` 不支持清单；`interp.go:657/:947` 的 panic 诊断路径 |
| 文件清单（唯一写者） | `impl/internal/interp/interp.go`（仅错误路径）、新增 `impl/internal/interp/unsupported_test.go` |
| 产出 | `@tasks`、任务 API、弱引用、`@arc/@gc` 等未实现构造 → 明确诊断 + 固定退出码，不 panic、不静默；诊断清单 |
| 验收 | `cd impl && go test ./internal/interp/ -run TestUnsupported -count=1` 全绿；每个构造一个负例；断言诊断文本与退出码 |
| 证据 | `evidence/S3-04/{summary.md,command.txt,exit_code.txt,stdout.txt,stderr.txt,sha.txt}` |
| 边界 | 不实现能力；不改 sema/xfront；E3 保留 interp 主责；本卡只改错误面 |

### S5-01　`Context` + 取消位 + deadline

| 项 | 内容 |
|---|---|
| 主责 / 必签 | RD3 / QA2 |
| 人日 / 就绪 / 依赖 | 1.5 / R2（Stage 4 门）/ S5-00 |
| 输入 | S5 §3.3/§5/§6；S3 §13；`xrt.h` 现状 |
| 文件清单（唯一写者） | 新增 `impl/runtime/rt_task.h`（冻结接口）、`impl/runtime/rt_task.c`、`impl/runtime/test_task.c` |
| 产出 | `Context.background()`、`checkCancel()`、`withDeadline()`；单线程取消位；单调时钟；到期等效取消 |
| 验收 | `cd impl/runtime && cc -std=c11 -Wall -Wextra -Werror -O2 -o /tmp/xn_test_task test_task.c rt.c rt_gc.c rt_weak.c rt_task.c && /tmp/xn_test_task` exit 0；断言 `checkCancel` 返回 `Cancelled`、deadline 不早于到期点 |
| 证据 | `evidence/S5-01/{summary.md,command.txt,exit_code.txt,stdout.txt,stderr.txt,sha.txt}` |
| 边界 | 单线程；不做线程池；不改 interp/codegen；不标 TASK-* PASS |

### S5-02　`TaskGroup` 单线程执行器 + `join`/`close`

| 项 | 内容 |
|---|---|
| 主责 / 必签 | RD3 / QA2 |
| 人日 / 就绪 / 依赖 | 2.0 / R2（Stage 4 门）/ S5-01 |
| 输入 | S5 §3.1/§3.2/§4；S3 §11.1；S5-01 的 `rt_task.h` |
| 文件清单（唯一写者） | `impl/runtime/rt_task.h`、`impl/runtime/rt_task.c`、`impl/runtime/test_task.c` |
| 产出 | ① 唯一 `spawn` 入口（无全局/detached）；② `close`=取消+等待终结（含清理完成）；③ `join` 一次性；④ 业务 `Err(E)` 原样交付、`kind()` 不降级；⑤ 未关组退出作用域触发运行时断言 |
| 验收 | 同一 `test_task` 命令 exit 0；TASK-01/02 正负例可单跑；重复 `join` 给明确错误；`close` 等待清理计数断言；无游离任务路径 |
| 证据 | `evidence/S5-02/{summary.md,command.txt,exit_code.txt,stdout.txt,stderr.txt,sha.txt}` |
| 边界 | 单线程执行器；不做并行执行器；不改 codegen/interp |

### S5-03　取消传播 + 清理路径 + `joinDeadline`

| 项 | 内容 |
|---|---|
| 主责 / 必签 | RD3 / QA2 |
| 人日 / 就绪 / 依赖 | 2.0 / R2（Stage 4 门）/ S5-02 |
| 输入 | S5 §5/§6/§10；S1 §10.3（`defer`/`errdefer`） |
| 文件清单（唯一写者） | `impl/runtime/rt_task.c`、`impl/runtime/rt_task.h`、`impl/runtime/test_task.c` |
| 产出 | ① 组取消向下传播；② `checkCancel` 以 `Cancelled` 终结；③ 无检查点任务在关闭时仍被等待；④ 清理路径不跳过、清理期间取消排队；⑤ `joinDeadline` 返回 `Err(Timeout)` 且不自动取消 |
| 验收 | 同一 `test_task` 命令 exit 0；CANCEL-01/02、TIMEOUT-01 各至少 1 正 1 负；取消后 `defer` 执行计数断言；无“立即中断”假承诺 |
| 证据 | `evidence/S5-03/{summary.md,command.txt,exit_code.txt,stdout.txt,stderr.txt,sha.txt}` |
| 边界 | 协作式取消；不承诺立即中断；不承诺硬实时 |

### S7-04　布局矩阵全表 + 未知错误码负例（FFI-02 / FFI-01）

| 项 | 内容 |
|---|---|
| 主责 / 必签 | QA1 / QA2 |
| 人日 / 就绪 / 依赖 | 1.5 / R1 / S7-01 |
| 输入 | S7 §3.1—§3.6、§7.1；`emit_test.go` 现有 `Pair` 夹具 |
| 文件清单（唯一写者） | 新增 `impl/internal/codegen/ffi/layout_matrix_test.go`；不改 `emit.go`/`check.go` |
| 产出 | ① 标量映射表逐项 size/offset；② `Bool/Char/Int32/Int64/Double/String/Bytes/标量数组`；③ `layout(c)` 多结构逐字段；④ 未标注 `struct` 只能封送/句柄；⑤ 未知错误码→`Internal` 负例 |
| 验收 | `cd impl && go test ./internal/codegen/ffi/ -run 'TestLayoutMatrix\|TestErrorCodeMatrix' -count=1` 全绿；每条断言具体值，不接受“能编译” |
| 证据 | `evidence/S7-04/{summary.md,command.txt,exit_code.txt,stdout.txt,stderr.txt,sha.txt}` |
| 边界 | 只新增测试文件；不改 FFI 实现；不标 FFI-02 PASS（测试通过后由 QA 独立签） |

### S7-05　trampoline 根登记/注销（FFI-05）

| 项 | 内容 |
|---|---|
| 主责 / 必签 | RD3 / QA1 |
| 人日 / 就绪 / 依赖 | 2.0 / R2（Stage 3+4 门）/ S7-01 + S3-03 |
| 输入 | S7 §5/§10；S3 §19/§22；`emit.go:174-188`（当前恒返 `ErrTrampolineReserved`） |
| 文件清单（唯一写者） | `impl/internal/codegen/ffi/emit.go`、新增 `impl/internal/codegen/ffi/trampoline_test.go`；如需 ABI 增补，`xrt_abi.c` 由 RD2 子卡承接 |
| 产出 | ① `EmitTrampoline` 创建时登记 `env` 为根；② 销毁时注销；③ 注销后再调用被检测；④ 回调内 panic 终止进程；⑤ 错误码出参映射（取消/超时不降级） |
| 验收 | `cd impl && go test ./internal/codegen/ffi/ -run TestTrampoline -count=1` 全绿；子进程断言 panic 退出码；注销后调用有明确诊断 |
| 证据 | `evidence/S7-05/{summary.md,command.txt,exit_code.txt,stdout.txt,stderr.txt,sha.txt}` |
| 边界 | 不改语言文法；trampoline 只存在于绑定层；回调 panic 不做任务级隔离 |

---

## 4. 依赖图与波次

```
S3-00 ──> S3-01 ──> S3-02
   └───────────────> S3-03 ──┐        （S3-03 还依赖 S5-02，见 PJ-2）
S5-00 ──> S5-01 ──> S5-02 ──┴──> S5-03
S7-00 ──> S7-01 ──> S7-02 ──> S7-03
              ├────> S7-04
              └────> S7-05（还依赖 S3-03）
S3-04 独立（写权：E3 书面确认）
```

| 波次 | 触发条件 | 卡片 | WIP 占用 |
|---|---|---|---|
| **W0** | 现在 | S3-00（RD2）、S5-00（QA1）、S7-00（RD3） | 二司 3 人各 1/1 |
| **W1** | S0-28 验收 + CEO1 放行 | S7-01（RD2）、S7-02→S7-03（CEO1-RD3）、S7-04（QA1）、S3-04（RD1） | 二司 RD1/RD2/QA1 各 1；跨司占一司 WIP |
| **W2** | Stage 2 门 | S3-01→S3-02（RD2） | RD2 串行 1/1 |
| **W3** | Stage 4 门 | S5-01→S5-02→S5-03（RD3）；S3-03 在 S5-02 后 | RD3 串行 1/1；RD2 接 S3-03 |
| **W4** | Stage 3+4 门 | S7-05（RD3） | RD3 1/1 |

关键路径：`S7-00 → S7-01 → S7-02 → S7-03` 与 `S5-01 → S5-02 → S5-03 → S3-03 → S7-05`。前者决定 FFI 用户路径，后者决定并发与任务根。

---

## 5. WIP 分配

| 角色 | 上限 | 本轮占用 | 队列（按序） | 备注 |
|---|---:|---|---|---|
| CEO2-RD1 | 1 | 0（待 W1） | S3-04 | interp 由 E3 保留主责；本卡只改错误面 |
| CEO2-RD2 | 1 | S3-00 | S7-01 → S3-01 → S3-02 → S3-03 | 串行，不并行接卡 |
| CEO2-RD3 | 1 | S7-00 | S5-01 → S5-02 → S5-03 → S7-05 | 串行；S7-04 由 QA1 主责 |
| CEO2-QA1 | 1 | S5-00 | S7-04 → 验收 S7-01/S3-01/S3-03/S7-05 | 验收也占 WIP，一次只签一张 |
| CEO2-QA2 | 1 | 0 | 验收 S3-02/S5-01/S5-02/S5-03/S7-04 | 与 QA1 分域，避免自写自签 |
| CEO2-PM | 2 | 首轮已交 | 条款复核 / 待决项跟进 | 不接实现卡 |
| CEO2-PJ | 2 | 本卡 | 看板同步 / 证据巡检 | 不接实现卡 |

**规则**：`待验` 仍占 WIP；一张卡未关闭，不接下一张；跨司卡不占二司 WIP（占 CEO1-RD3 的 1/1）。

---

## 6. 证据路径

```
evidence/
├─ S3-00/  S3-01/  S3-02/  S3-03/  S3-04/
├─ S5-00/  S5-01/  S5-02/  S5-03/
└─ S7-00/  S7-01/  S7-02/  S7-03/  S7-04/  S7-05/
```

每目录六件套见 §1.4；回执统一 `收件箱/CEO2/回执-<卡号>-<主责>.md`。
跨司卡（S7-02/03）证据仍落根 `evidence/`，由主责采集，二司只做 ABI 会签。

**已知反面样例**：S0-28 证据只在 `wt/e6-toolchain/evidence/S0-28/`，根目录缺失；本轮所有卡禁止复现该形态。

---

## 7. 阻塞与升级（15 项，一次列全）

| # | 事项 | 事实 | 影响卡 | 需要谁定 |
|---|---|---|---|---|
| B1 | S0-28 未验收、根目录无证据 | `81ec33d` 已交付；`evidence/S0-28/` 只在 E6 worktree | 全部 R1/R2 | CEO1 验收；董事会授权合 main |
| B2 | 阶段门未到 | Stage 2/4 未过；R2 卡不能落代码 | S3-01/02/03、S5-01/02/03、S7-05 | 董事会/CEO1 |
| D-1 | 条款语句级 ID 缺失 | S3/S5/S7 只有节号；`PM-S3-xx` 不是台账锚点 | 全部验收 | 董事会 / S0-14 主责 |
| D-2 | S5 三个锚点缺行 | `CANCEL-01/02`、`TIMEOUT-01` 未进 101 表 | S5-00/S5-03 | 董事会 / CEO3 |
| D-3 | MEM-11 与 FFI-01/03 重叠 | 同一合同三个锚点，签一次还是两次未定 | S7-01/S7-04 | CEO1（L2）/ 二司 QA |
| D-4 | 台账里程碑口径冲突 | FFI 行记 `M3`，阶段规划为 Stage 7 | S7-* | 董事会 / 三司 |
| D-5 | S3 §18 与 XDK-09 跨司 | 句柄合同约束在 S3、类型在 S6 | S3-01/S7-01 | CEO2 / CEO3 |
| D-6 | 并发安全无法取证 | ASan 本机 SIGILL；根表/链表/弱表单线程非原子；`xrt_safepoint` 不触发 GC | S3-00/01/02、S5-* | 董事会技术结论（CTO1/CTO2） |
| D-7 | FFI 属性与 `@unsafe` 落点 | 绑定层注解已定，但“应用代码不可创建”需编译器支持 | S7-05 | 董事会 / 一司+二司 |
| B2-RD3 | 单线程结构化并发能否签 `TASK-*` | 并行执行器未做 | S5-02/S5-03 | 董事会 / 二司 PM |
| B3 | `xdk.tasks`/`xdk.sync` 签名归属 | S6 只给类型名，无成员签名 | S5-01/02/03 | 二司 PM + 一司 PM |
| B4 | codegen 跨司子卡如何派 | `impl/internal/codegen/**` 属一司 | S7-02/S7-03 | CEO2 / CEO1 |
| B5 | INV-FFI-5 的 pin 口径 | 当前实现是“canary 拷贝”而非 pin | S7-01/S7-04 | CTO 评审 |
| **PJ-1** | `status.tsv` 写权 | QA 只能出补丁，不能改表 | S5-00 | 董事会 / CEO3 |
| **PJ-2** | **阶段依赖顺序冲突** | `MEM-09` 属 Stage 3，却依赖 Stage 5 的任务模型；Stage 3 退出条件“11/11 PASS”无法独立达成 | S3-03、S3 阶段门 | 董事会 |

`PJ-2` 建议三个选项，供董事会裁决：

- **A**：Stage 3 退出条件改为 `MEM-01—08、10—13`，`MEM-09` 移入 Stage 5 退出条件（改动最小，但阶段表要改）。
- **B**：Stage 3 内先落“任务根最小骨架”（仅 root 绑定/解除，不做调度），S5 再补完整任务模型（会引入 Stage 3 内的 S5 子集）。
- **C**：调整阶段顺序，把 Stage 5 提到 Stage 3 之前（影响面最大，不推荐）。

未裁决前，`S3-03` 不得开工；`S7-05` 同步等待。

---

## 8. 未拆卡锚点（backlog，非本轮遗漏）

| 锚点 | 未来卡 | 为什么不在本轮 | 触发条件 |
|---|---|---|---|
| MEM-05 栈分配 | S3-05 | 依赖 S2 逃逸分析落地 | Stage 2 门 |
| MEM-06 容器扫描/`clear` | S3-06 | 依赖一司 codegen 容器表示 | 容器 codegen 冻结 |
| MEM-07 `Result` 盒 | S3-07 | 待 S3 §20 内联决策 | 内联方案定稿 |
| MEM-10 清理责任 | S3-08 | 跨一司 `defer`/`codegen` | 一司派子卡 |
| MEM-12 确定性 | S3-09 | 依赖 CI 产物与转储格式 | CI 九项全绿 |
| MEM-13 优化 | S3-10 | 每项单独立项 | 逐项评审 |
| TASK-04 任务 panic | S5-04 | 依赖 S5-02 执行器 | S5-02 通过 |
| SYNC-01 `Mutex` | S5-05 | 本轮容量已满 | S5-03 通过 |
| SYNC-02/03 `Channel`/`Atomic` | S5-06 | 同上 | S5-05 通过 |
| BLOCK-01 `@tasks` | S5-07 | 跨一司文法 | 一司文法排期 |
| SCHED-01 调度分类 | S5-08 | 依赖 S6 XDK 与 S7 分类清单 | S6/S7 清单齐 |
| FFI-04 `@unsafe` | S7-06 | 跨一司 sema | 一司支持受控入口 |
| FFI-07 阻塞实测 | S7-07 | 依赖 S5 调度 | S5-08 通过 |
| S7 §4.3 句柄并发 | S7-08 | 依赖 S5-02 | S5-02 通过 |
| MEM-11 缓冲区 pin | S7-09 | 待 B5 口径 | CTO 裁决 |

---

## 9. 拆卡自检

| 项 | 结果 |
|---|---|
| 卡数 | 15（≥8 要求满足） |
| 人日 | 最大 2.0、最小 1.0，无超限 |
| 单一主责 | 15/15 |
| 必签 ≠ 主责 | 15/15 |
| 依赖无环 | 卡级 15/15 无环；阶段级存在 `S3 → S5 → S3` 回边（MEM-09），已升级 `PJ-2` |
| 证据路径 | 15/15 已定 |
| 就绪分级 | R0 3 / R1 5 / R2 7 |
| 跨司卡 | 2 张（S7-02、S7-03），主责在一司 |
| 未决项 | 15 项已列（§7），无隐藏假设 |

**本轮边界自证**：只读文件、只跑构建与测试；未编辑 `impl/**`、未改 `status.tsv`/台账/看板；未 commit、未 push、未派工。唯一写入为本文件。

---

**CEO2PJ READY**
