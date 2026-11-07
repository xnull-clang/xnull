# CEO2-RD3 首轮盘点：并发与 FFI（只读）

> **角色：CEO2-RD3-并发与FFI**（二司·运行时）　**依据：董事会判决 v1.6.0 第 2/5 条**
> **域：`impl/runtime/**`（任务/并发部分）+ `impl/internal/codegen/ffi/**`**　**日期：2026-11-07**
> **性质：只读盘点。未改生产代码、未 commit、未派工、未触碰他人文件。**
> **复核基线：`main` @ `dfcf033`，工作区有他人未提交改动（`日志/`、`收件箱/` 等），本报告不依赖其内容。**

---

## 0. 结论（先看这六条）

1. **并发是 0，不是"部分"**：语言层只有 `async/await/yield` 三个词法 token（`impl/internal/xfront/token.go:125`），无解析、无语义、无执行；`xdk.tasks`/`xdk.sync` 只登记了符号名（`impl/internal/sema/xdk.go:36-42`），无签名、无实现；`impl/runtime` 内无调度器/线程/通道/互斥量任何符号。S5 的 12 项验收（TASK/CANCEL/TIMEOUT/SYNC/SCHED/BLOCK）在 `impl/docs/conformance/status.tsv` 中**只有 `BLOCK-01` 一行且标注"未实现"**，其余 11 项连行都没有。
2. **FFI 是一颗"造好了但没上膛的子弹"**：`.xfb` 解析/合同校验/包装生成/错误码归一/句柄幂等关闭都已完成且有端到端测试（`impl/internal/codegen/ffi/**`，`go test ./internal/codegen/ffi/` 实测通过，102.8s）；但 **codegen 里没有任何 `FFICall` 钩子**，`xnull build` 也**不链接 `xrt_abi.c` 与 `rt_std_*.c`**（`impl/internal/codegen/build.go:44-48`）。也就是说，用户写 `.x` 源码今天无法调用任何一个 FFI 入口。
3. **ABI 有两条脸，且互相不认**：生成的 XNull C 代码直接 `#include "rt.h"` 并调用 `rt_*`（`impl/internal/codegen/codegen.go:27-31`，全仓 80 处 `rt_string` 相关引用），而 FFI 包装只 `include xrt.h` 并调用 `xrt_*`（`impl/internal/codegen/ffi/emit.go`）。`runtime-contract.md` P-08 明确要求"`xrt.h` 为唯一对外 ABI 头，`rt.h` 降级为内部头，codegen 迁移挂 M4.4a"——**该迁移未执行**，与 S3 §22 / S7 §9 INV-FFI-7 直接冲突。
4. **初始化顺序合同未落实**：S7 §6.3 规定"`xrt_runtime_init` 之前不得创建对象"，但生成的 `main` 只调 `rt_quarantine_flush()`，**从不调用 `xrt_runtime_init`**（`impl/internal/codegen/codegen.go:308-310`）；全仓仅 `impl/runtime/test_abi.c:50` 调用过它。
5. **三项 ABI 是"桩"，不是"实现"**：`xrt_write_barrier` 只检查 terminated 标志、无屏障（`impl/runtime/xrt_abi.c:57-63`）；`xrt_safepoint` 只是隔离区 flush（`:69-73`）；`xrt_task_root_bind/unbind` 直接映射到**进程级** GC root 增删（`:77-79`），不是 S3 §11 要求的"任务 env external root"。GC 根表与对象链表是**无锁全局链表**（`impl/runtime/rt_gc.c:14-18`），接多线程即数据竞争。
6. **缺口可以按"先打通、再并发、后压测"三段补齐**：见 §5 的 3 张建议卡与 §4 的 10 条测试缺口。当前最大风险不是"并发没做"，而是**没有一条用例能证明"并发没做"**——能力缺口表一旦被读成"部分支持"，就是假绿。

---

## 1. 并发现状（S5 + S3 §11）

### 1.1 能力矩阵

| 面 | 规范锚点 | 现状 | 证据 |
|---|---|---|---|
| 语言关键字 `async`/`await`/`yield` | S1 附录 A | 仅词法 token；无 AST 节点、无解析分支、无语义 | `impl/internal/xfront/token.go:125`；`impl/internal/xfront/lexer_test.go:387` 只断词法 |
| `@tasks` 块注解 | S5 §2.3 / BLOCK-01 | 无任何识别；注解通用节点存在但无消费方 | `impl/internal/sema/**` 无 `tasks` 注解处理；`status.tsv:24` BLOCK-01=未实现 |
| `xdk.tasks` 符号 | S6 §4.2 | 只登记 `Task`/`TaskGroup`/`Context` 三个名字 | `impl/internal/sema/xdk.go:36-39` |
| `xdk.sync` 符号 | S6 §4.3 | 只登记 `Mutex`/`Channel`/`AtomicInt`/`AtomicBool`/`AtomicRef` 五个名字 | `impl/internal/sema/xdk.go:40-42` |
| 类型签名 / 成员 | S5 §3 / 附录 A | 无：`group.spawn`、`t.join()`、`ctx.checkCancel()` 全部不可解析 | 无对应代码；XDK 注册表只有 `map[string]bool`（`xdk.go:33`） |
| 解释器 | S5 全节 | 无任务/闭包值；遇不支持构造直接 panic 为诊断 | `impl/internal/interp/interp.go:657`、`:947`；`impl/README.md`「不支持（后续切片）」含闭包值 |
| 调度器 | S5 §2.2 | 无：`impl/runtime` 无 thread/scheduler/mutex/channel 符号 | `grep -rniE "task\|schedul\|thread\|mutex" impl/runtime/*.h` 仅命中 ARC 原子计数与 `xrt.h:63-64` 的 `xrt_task_root_*` 声明 |
| 取消 / 超时 | S5 §5/§6 | 无 `Context`、无取消传播、无定时器 | 无代码 |
| `Atomic*` | S5 §7.1 / SYNC-03 | 无公开原子原语；仅内部 ARC 计数用 C11 atomics | `impl/runtime/rt.h:48`（`atomic_int_fast64_t refcount`） |
| 任务 env 根 | S3 §11.1 / MEM-09 | ABI 入口在，语义是进程级 root | `impl/runtime/xrt_abi.c:77-79` → `rt_gc_root_add/remove` |
| 跨任务句柄 | S7 §4.3 / ffi-contract §5.2 | 明确"随调度器切片"，当前单线程假设 | `impl/docs/ffi-contract.md` §5.2；`xrt_abi.c:149-165` `closed` 为普通 `int` |
| GC 并发安全 | S3 §8/§12 / MEM-03/04 | 根表 `g_roots`、GC 链表 `g_gc_list` 均为无锁全局可变状态 | `impl/runtime/rt_gc.c:14-18`、`:50-77` |

### 1.2 判断

- S5 是**整段空白**，不是"实现了一部分"。任何下游能力（异步 I/O、`xdk.net`、`xdk.ui` 线程归属）都被 S5 §9 的发布门槛挡住。
- 解释器路线也走不通并发：任务 API 的入口形态是**闭包**，而解释器连闭包值都不支持（`impl/README.md`）。所以 S5 不能靠解释器"先跑通"，必须直接落到 C 运行时 + codegen。
- 现有运行时是**单线程顺序执行**（`ffi-contract.md` §5.2 自述），ARC 计数虽是原子的，但 GC 根表、隔离区、句柄状态都不具备并发安全。加线程前必须先定"STW 还是安全点"（S3 §13），否则退化。

---

## 2. FFI 现状（S7）

### 2.1 已完成（可验收部分）

| 能力 | 状态 | 证据 |
|---|---|---|
| `.xfb` 词法/语法/合同校验（FFI-100—111） | 完成，12 类负例 | `impl/internal/codegen/ffi/check.go`、`parser.go`、`lexer.go`；`ffi_test.go:175 TestContractNegatives` |
| 注册表确定性（按入口名排序） | 完成 | `ffi_test.go:107 TestLoadPositiveAndDeterministic` |
| 包装生成：标量 / `String` / `Bytes`(borrow) / 数组 / `layout(c)` / 句柄 transfer·reclaim·borrow | 完成 | `impl/internal/codegen/ffi/emit.go:94 EmitCall`、`:112 EmitSupport`；`emit_test.go:206` 端到端 cc 编译运行 |
| 错误码归一（未知码→`Internal`，绝不当 `Ok`） | 完成 | `emit.go:278-289`；`emit_test.go:258` 断言 `unknown=Internal` |
| canary 越界检测（进程终止） | 完成 | `emit_test.go:206` 子进程 `canary` 模式 |
| 句柄 close 幂等 / `.reclaim` 归还登记 | 完成 | `xrt_abi.c:127-179`；`test_abi.c`；`emit_test.go` `close_total=1` |
| 阻塞分类清单机制（manifest↔文档同步） | 完成 | `emit.go:196-216 BlockingManifest`；`xdk_test.go:189` |
| trampoline / 回调根登记 | **仅接口预留** | `emit.go:174-188` 恒返 `ErrTrampolineReserved`；`emit_test.go:299` 只断言"返回预留错误" |

### 2.2 绑定面（12 入口，0 个长阻塞）

| 区域 | 入口 | 分类 |
|---|---|---|
| `xdkc_runtime` | diagnose / exit / nowMono / nowWall | 全 `.aware` |
| `xdkc_sys` | fileOpenRead / fileRead / fileWrite / dirOpen | `.unaware` |
| `xdkc_sys` | fileClose / dirRead / dirClose / pathExists | `.aware` |

- 与 `impl/docs/blocking-classification.md` 逐行一致（`xdk_test.go:189` 机械核验）。
- **`@longRunning` 实例为 0**，因此 `submit<Entry>` 伴生形态从未被真实用例驱动；`check.go:411-416` 的 FFI-107 校验只有"缺伴生入口"负例（`emit_test.go:318`/`ffi_test.go:154` 的 `ffiSqliteExec` 是测试夹具，不入仓库绑定）。
- `.unaware` 分类**没有任何实测计时**：`fileRead`/`fileWrite` 在慢盘、网络盘上就是长阻塞，但规则要求长阻塞才加 `@longRunning`；当前分类是否如实，无可执行判据（见 §4 缺口 G8）。

### 2.3 未接通的两段（本报告最重要的 FFI 事实）

1. **codegen 侧无 `FFICall` 钩子**：`grep -rnE "FFICall|codegen/ffi|EmitCall" impl/internal/codegen/*.go` 为空（退出码 1），仅 `ffi` 包内部与测试互相调用。`impl/docs/ffi-contract.md` §5 自己写着"codegen 侧 `FFICall` 钩子：待编译器侧接入（提案 P-09）"。
2. **构建侧无 ABI 层**：`impl/internal/codegen/build.go:44-48` 的 cc 清单是 `rt.c / rt_gc.c / rt_policy.c / rt_weak.c` 四个文件，**没有 `xrt_abi.c`、没有 `rt_std_*.c`、没有 `LinkArgs`**。P-10 四条条件（import 闭包、同批切换、去重升序、缓存键）一条都没落地。
3. **无用户路径**：`examples/*.x` 里 `grep xdk` 零命中，没有任何示例或测试从 `.x` 源码走到 FFI 包装。

结论：FFI 子系统本身质量不错，但**当前对用户的价值是 0**；它的"完成度"只对内部测试成立。

---

## 3. ABI 边界

### 3.1 设计意图（四层）

```
.x 源码
  └─ codegen（Go，AST→C）            ← 应当只经 xrt.h（S3 §22 / INV-FFI-7）
       ├─ 普通生成代码 → xrt_*        ← 现状：直接 rt_*，include rt.h
       └─ ffi 包装片段 → xrt_*        ← 现状：合规（只 include xrt.h）
            └─ xrt_abi.c 薄封装 → rt_*（内部头，不分发）
                 └─ rt.c / rt_gc.c / rt_policy.c / rt_weak.c
```

### 3.2 冻结面（S7 §6.1）与实际实现对照

| S7 §6.1 入口 | `xrt.h` 签名 | 实现 | 判定 |
|---|---|---|---|
| 分配 `xrt_alloc` | `(xrt_kind, const xrt_type*)` | `xrt_abi.c:29-40` | 符合；GC 缺 scan → fatal |
| 计数 `xrt_retain`/`xrt_release` | `void*` / `void` | `rt_*` 直通 | 符合 |
| 弱表 `xrt_weak_bind/read/clear` | 不透明 `xrt_weak_slot*` | `rt_weak_*` 直通 | 符合；但"只对 FFI 合同层开放"无机械约束 |
| 屏障 `xrt_write_barrier` | `(void*)` | **只查 terminated，无屏障** `xrt_abi.c:57-63` | **桩**（S3 §12 要求覆盖字段写入/扫描链维护） |
| 根 `xrt_register_root`/`unregister` | `(void*)` | `rt_gc_root_add/remove` | 入口在，但**codegen 从不调用**（全局根登记未落地，A3） |
| 安全点 `xrt_safepoint` | `void` | 仅 `rt_quarantine_flush()` `:69-73` | **桩**（不覆盖任务挂起点，S5 §9） |
| 任务根 `xrt_task_root_bind/unbind` | `(void*)` | 映射进程级 GC root `:77-79` | **语义不符**（S3 §11 / MEM-09 要的是任务作用域） |
| 初始化 `xrt_runtime_init` | `void`，幂等 | `:16-22`，无实质初始化 | 有；但**生成产物从不调用** |
| 字符串 / `xrt_bytes` / `xrt_handle` / `xrt_fatal` | 见头文件 | 全部实现 | 符合 |

### 3.3 六条偏差（按严重度）

| # | 偏差 | 规范冲突 | 位置 |
|---|---|---|---|
| A1 | 生成代码直接 `include rt.h` 并调 `rt_*`，绕开稳定 ABI | S3 §22「只通过这些入口」、S7 INV-FFI-7、P-08「`rt.h` 降级内部头」 | `impl/internal/codegen/codegen.go:27-31`、`:293-294`；`build.go:44-48` |
| A2 | 生成 `main` 不调 `xrt_runtime_init`，违反"init 之前不得创建对象" | S7 §6.3 | `codegen.go:308-310` |
| A3 | `rt_std_*.c` / `xrt_abi.c` 不在构建清单，FFI 包装编不进来 | P-10 条件 1/2、S7 §6.1 | `build.go:44-48` |
| A4 | `xrt_write_barrier` / `xrt_safepoint` 是桩，并发下不能保护引用交换 | S3 §12/§13、S5 §9 | `xrt_abi.c:57-73` |
| A5 | `xrt_task_root_bind` 是进程级 root，无法表达"任务终结即解除" | S3 §11.1、MEM-09 | `xrt_abi.c:77-79` |
| A6 | 句柄 `closed` 非原子；close/use 并发竞争未定义 | S7 §4.3、ffi-contract §5.2（已明写"随调度器切片"） | `xrt_abi.c:109-113`（`int closed`）、`:149-165` |

补充：`xrt.h` / `xrt_abi.c` / `rt.h` 在 `impl/` 与公开副本 `xnull/impl/` 逐字节一致（本轮 diff 通过）；但 `impl/internal/codegen/*.go` 两副本已漂移，属一司范围，本报告只登记不处置。

---

## 4. 测试缺口（10 条，按投产阻断度排序）

> 判定口径：**能复现、能断言、能进 `status.tsv`** 才算用例；"跑了没崩"不算。

| # | 缺口 | 现状证据 | 风险 | 建议验收锚点 |
|---|---|---|---|---|
| G1 | **S5 全矩阵零行为用例**：status.tsv 只有 `BLOCK-01` 一行（未实现），其余 11 项无行；`impl/internal/**/*_test.go` 与 `impl/runtime/test_*.c` 均无并发行为用例（仅 `sema/xdk_test.go:29` 的导入诊断） | `impl/docs/conformance/status.tsv` 全文 36 行 | 任何"支持并发"的对外表述都不可证；S4 能力缺口表会长期假绿 | TASK-01/02/03/04、CANCEL-01/02、TIMEOUT-01、SYNC-01/02/03、SCHED-01、BLOCK-01 |
| G2 | **`@tasks` / 任务 API 的负向拒绝用例缺失**：无"块外 spawn 被拒"、无"`Mutex<struct>` 被拒"、无"Guard 逃逸被拒" | lexer 只断 token（`lexer_test.go:387`）；`status.tsv:24` BLOCK-01=未实现 | 编译器可能静默接受非法并发形态，把错误推到运行时 | BLOCK-01、SYNC-01 |
| G3 | **任务根语义未测**：`test_abi.c:100-103` 只测 bind/unbind 不崩，不测"存续期可达、终结后可回收" | `impl/runtime/test_abi.c:100-103` | MEM-09 无法签；env 可能提前回收或永久泄漏 | MEM-09 / TASK-03（GC 压力） |
| G4 | **ABI 初始化顺序未测**：无"未 init 创建对象应违约"用例；生成产物根本不调 init | `codegen.go:308-310`；`test_abi.c:50-51` 仅幂等 | S7 §6.3 合同形同虚设；嵌入方按文档写会踩空 | FFI-06 / 新增 ABI-INIT-01 |
| G5 | **`xnull build` 产物符号面未测**：无测试断言产物链接了 `xrt_abi.c`/`rt_std_*.c`，也不检查 `xrt_*` 符号存在 | `build.go:44-48`；`emit_test.go` 自带 cc 清单（`emit_test.go:236-240`）恰好掩盖了 build 的缺失 | FFI-06 只能"部分"；构建回归无法被捕获 | FFI-06（`nm` 断言 + 原生 TU `#include "xrt.h"` 链接） |
| G6 | **FFI 调用链端到端缺**：无 `.x` 源码 → `FFICall` → `xn_ffi_*` → Result 的用例；错误码→`Result` 映射零覆盖 | codegen 无 `FFICall`（`grep` 为空）；`examples` 无 xdk | INV-FFI-2 的编译器侧一半无证据；未知码可能被当 Ok | FFI-01 / BOUND-02（负例：未知码必须 `Internal`） |
| G7 | **trampoline 零覆盖**：`EmitTrampoline` 恒返预留错误，无"注销后调用被检测"用例 | `emit.go:174-188`；`emit_test.go:299` 只测返回错误 | INV-FFI-6 / FFI-05 永远是"部分" | FFI-05 |
| G8 | **阻塞分类只做文本同步，不做行为实测**：`fileRead`/`fileWrite`/`dirOpen` 标 `.unaware`，但无慢 I/O 计时；`@longRunning` 实例为 0 | `xdk_test.go:189` 仅比对文档行；`check.go:411-416` | 分类错误是被规范点名的"合同违规"（S5 §2.2 / S7 §7.3），却无可检出手段 | SCHED-01 / FFI-07（至少一条 `.unaware` 实测 + 一条 `longRunning` 夹具） |
| G9 | **跨任务句柄规则未测**：无并发 close/use 用例；`closed` 非原子 | `xrt_abi.c:109-113`；`ffi-contract.md` §5.2 自述"随调度器切片" | 双线程 close 可能双调 close_fn 或 use-after-close | S7 §4.3 / INV-FFI-9（并发版） |
| G10 | **布局矩阵单薄**：`layout(c)` 只有 `Pair{Int64,Int32}` 一个结构；`FFI-02` 仍"部分" | `emit_test.go:206`（`xn_layout_Pair_check`） | 标量映射表逐项正确性（S7 §3.2）无证据；跨平台 ABI 差异漏检 | FFI-02（Bool/Char/Int32/Int64/Double/String 全表 size/offset 断言） |

**次级缺口（先登记，不单独立卡）**：

- `String`/`Bytes` 的 pin 语义与"canary 拷贝"实现不一致：S7 INV-FFI-5 要求"借出缓冲区边界期间存活且 pin"，当前实现是拷贝进出（`emit.go` Bytes 分支），语义上是"不跨界"而非"pin"。需在合同里写清"实现采用拷贝等价形态"，否则 INV-FFI-5 无法签。
- `rt_gc.c` 的 `g_roots` 删除是 swap-with-last（`rt_gc.c:70-77`），单线程无影响，但会让"根集合顺序"不确定；DET-01 不涉及输出，暂不立卡。
- `impl/` 与 `xnull/impl/` 的 codegen 已漂移；FFI/运行时文件未漂移。

---

## 5. 前 3 张建议卡（待 CEO2 派工、PJ 定 S 编号）

> 说明：卡号为**建议编号**，最终以 PJ 的 `S<阶段>-<序号>` 为准；本报告不派工。
> WIP 约束：一人同时只 1 张；下面三张分属 RD3 / RD2 / QA1，互不撞车。
> 写入前提：`evidence/S0-28/` 不存在 → worktree 写权**未解禁**（与一司判定同口径）。三张卡开工前均需 S0-28 验收通过 + 文件级任务卡。

### 卡 1（建议 `S5-01`）并发最小骨架：单线程执行器 + Context/TaskGroup

| 项 | 内容 |
|---|---|
| 主责 | **CEO2-RD3**（并发）；必签 CEO2-RD2（运行时/ABI） |
| 输入 | S5 §2/§3/§4/§5/§6、S3 §11/§13、`impl/runtime/xrt.h` 现状 |
| 范围 | 只做**单线程、可取消、结构化**的最小骨架：`Context`（取消位 + deadline 单调时钟）、`TaskGroup`（唯一 spawn、close=取消+等待）、`Task.join`（一次性）、`checkCancel`/`withDeadline` 语义；线程池/并行执行**明确不做**（下一卡） |
| 产出 | `impl/runtime/` 新增 `rt_task.{h,c}`（内部）+ `xrt_task_*`（ABI）；单线程事件队列；任务根改为**任务作用域**（修复 A5）；`test_task.c` 覆盖 TASK-01/02、CANCEL-01/02、TIMEOUT-01 的**单线程可测部分** |
| 验收 | `cc -std=c11 -O2 -Wall -Wextra -Werror` 零警告；`test_task` 全绿；`status.tsv` 新增 TASK/CANCEL/TIMEOUT 行并给用例名；`xrt_task_root_bind` 在任务终结后可回收（GC 压力断言） |
| 依赖 | 无（不依赖 codegen）；与卡 2 的 ABI 冻结面**只增不改** |
| 预估 | 3 人日（RD3）；评审 0.5 人日（RD2） |
| 证据 | `evidence/S5-01/`（命令输出 + `test_task.c` 运行日志 + status.tsv diff） |
| 风险 | `defer`/`errdefer` 在取消路径的清理顺序（S5 §5）；若解释器先行，会出现两套语义，**本卡禁止改解释器** |

### 卡 2（建议 `S7-01`）ABI 收口 + FFI 调用链打通

| 项 | 内容 |
|---|---|
| 主责 | **CEO2-RD2**（运行时/内存/ABI）；必签 CEO2-RD3（FFI 合同面）、CEO1-RD3（codegen 接入子卡） |
| 输入 | P-08/P-09/P-10 及 C 段四条条件（`impl/docs/runtime-contract.md:42-59`）、`impl/docs/ffi-contract.md` §2/§5.1、S7 §6/§7 |
| 范围 | ① codegen 生成代码从 `rt_*`/`rt.h` 迁到 `xrt_*`/`xrt.h`（A1）；② 生成 `main` 注入 `xrt_runtime_init()`（A2）；③ `build.go` 链接清单纳入 `xrt_abi.c` + 按 import 闭包的 `rt_std_*.c`，`LinkArgs` 去重升序（A3）；④ 接入 `ffi.Load`/`EmitCall`/`EmitSupport` 的 `FFICall` 钩子 + 错误码→`Result` 映射（G6） |
| 子卡拆分（禁止两人改同一文件） | 2a RD2：`impl/runtime/xrt_abi.c` + `impl/runtime/xrt.h` 收口（含 init 顺序断言）；2b CEO1-RD3：`impl/internal/codegen/codegen.go` 迁 `xrt_*` + `FFICall`；2c CEO3-RD2：`impl/internal/codegen/build.go` 链接清单 + LinkArgs（跨司，需 CEO2 协调） |
| 产出 | 生成产物 `nm` 可验 `xrt_*` 符号；`.x` 示例调用一条 `xdkc_*` 入口并输出 `Result`；`status.tsv` FFI-06/FFI-01 升 PASS |
| 验收 | 全量 `go test ./... -count=1` + `xnull build` 产物 `nm` 断言 + 负例"未知码→Internal 不得 Ok"；`examples/ffi-hello.x` stdout 与退出码固定 |
| 依赖 | 卡 1 的 ABI 增补（任务根）可并行；2c 依赖 2a/2b 同批合入（P-10 条件 2） |
| 预估 | 4 人日（2a 1.5 / 2b 1.5 / 2c 1） |
| 证据 | `evidence/S7-01/`（`nm` 输出、端到端 stdout、负例诊断、LinkArgs 快照） |
| 风险 | `rt.h`→`xrt.h` 迁移面大（全仓 80 处 `rt_string` 相关引用），必须一次性切完，**禁止中间态双面链接**；codegen 属一司域，需正式跨司子卡 |

### 卡 3（建议 `S5-02`/`S7-02`）并发与 FFI 验收基建：把 §4 的缺口变成可执行用例

| 项 | 内容 |
|---|---|
| 主责 | **CEO2-QA1（运行时验收）**；必签 CEO2-RD3 |
| 输入 | S5 §10 全矩阵、S7 §10 全矩阵、S3 §25（MEM-04/09/11）、本报告 §4 的 G1–G10 |
| 范围 | 只写测试与夹具，不改生产代码：①`status.tsv` 补齐 S5 12 行 + FFI 缺失行；②ABI 链接测试（原生 TU `#include "xrt.h"`，`nm` 断言稳定符号）；③初始化顺序负例；④阻塞分类实测夹具（慢 I/O 桩 + `longRunning` 夹具）；⑤GC 安全点/任务挂起用例（可与卡 1 并行，先写失败用例） |
| 产出 | `impl/internal/**/*_test.go` / `impl/runtime/test_*.c`（或分派测试文件）+ 每行 status 的用例名 + 假绿风险清单 |
| 验收 | 每条用例可单跑：`go test -run <Name>` 或 `cc && ./test_*`；失败必须是**明确诊断**，不得 skip 掩盖；G1–G10 每条有处置（立用例 / 明确 N/A 理由） |
| 依赖 | 卡 1/卡 2 交付前可先写"红"用例；不得在测试里给生产代码放水（禁 `t.Skip` 兜底） |
| 预估 | 3 人日 |
| 证据 | `evidence/S5-02/`（逐用例命令 + 输出 + status.tsv diff） |
| 风险 | 测试文件写权需分派；`test_abi.c` 是 RD2 域，QA 只能新增文件，不改既有 |

### 为什么是这三张（排序理由）

1. **并发先做"单线程结构化"而不是直接上线程池**：S5 的验收主体（组/取消/超时/错误交付）在单线程事件循环下就能全部证明；并行执行只影响 SCHED-01 的"不占载体线程"一条。先啃 12 项里的 9 项，风险最低。
2. **ABI 收口与 FFI 打通必须同批**：P-10 条件 2 已经明写"避免中间态双面链接"，拆开做等于制造两套 ABI 同时在线。
3. **验收基建不能等实现完**：现在最危险的是"没有失败用例"，不是"没有实现"。QA 先写红用例，才能防止后续实现用"能跑就算过"收尾。

---

## 6. 阻塞与待决（需要上级/董事会裁决，不自行决定）

| # | 事项 | 需要谁定 | 影响 |
|---|---|---|---|
| B1 | `evidence/S0-28/` 缺失 → 9 个 worktree 写权未解禁 | 董事会 / CEO1 门禁 | 三张卡全部无法开工 |
| B2 | 并发验收的"支持"口径：单线程结构化并发是否可标 `TASK-*` PASS，还是必须等并行执行器 | 董事会 / PM（二司） | 决定卡 1 能否关闭 TASK-02 |
| B3 | `xdk.tasks`/`xdk.sync` 的成员签名归 S6 母本还是实现层冻结（S6 §4.2 只给类型名） | PM（二司）+ 一司 PM | 卡 1 的 API 形态无母本可依 |
| B4 | codegen 迁 `xrt_*` 属一司文件，跨司子卡如何派（CEO2 协调 vs 董事会直派） | CEO2 / CEO1 | 卡 2 的 2b/2c 能否启动 |
| B5 | INV-FFI-5 的"pin"是否接受"canary 拷贝等价形态" | CTO 评审 | FFI-03/INV-FFI-5 的判定口径 |

---

## 7. 复核命令（可复制，全部只读）

```bash
# 1) FFI 包全量（含 cc 端到端，约 100s）
cd impl && go test ./internal/codegen/ffi/ -count=1

# 2) ABI 层自测
cd impl/runtime && cc -std=c11 -O2 -Wall -Wextra -Werror -I. \
  -o /tmp/xn_test_abi test_abi.c rt.c rt_gc.c rt_weak.c xrt_abi.c && /tmp/xn_test_abi

# 3) 并发零实现核对（应只命中词法 token 与 ARC 计数）
grep -rniE --include=*.go --include=*.c --include=*.h "task|spawn|async|await|schedul|concurren" impl/internal impl/runtime

# 4) 构建清单核对（应无 xrt_abi.c / rt_std_*.c）
grep -n "exec.Command" -A6 impl/internal/codegen/build.go

# 5) 生成代码 ABI 面核对（应命中 rt.h / rt_* / 无 xrt_runtime_init）
grep -n "include \"rt\|rt_quarantine_flush\|xrt_runtime_init" impl/internal/codegen/codegen.go

# 6) 并发相关 status 行（当前应只有 1 行：BLOCK-01 未实现）
grep -nE "^(TASK|CANCEL|TIMEOUT|SYNC|SCHED|BLOCK)-" impl/docs/conformance/status.tsv

# 7) FFI 钩子是否接入 codegen（无输出 = 未接入）
grep -rnE "FFICall|codegen/ffi|EmitCall" impl/internal/codegen/*.go

# 8) 本轮实测记录
#    go test ./internal/codegen/ffi/  → ok 102.794s
#    test_abi                      → abi 测试通过
```

---

## 8. 本轮边界（自证未越权）

- 只读文件、只跑测试与 `grep`/`diff`；未编辑 `impl/**`、未编辑 `bindings/**`、未改 `status.tsv`/台账/看板。
- 唯一写入：本文件 `收件箱/CEO2/CEO2RD3-首轮.md`。
- 未 commit、未 push、未派工、未建卡（§5 仅为建议，最终派工权在 CEO2/PJ）。
