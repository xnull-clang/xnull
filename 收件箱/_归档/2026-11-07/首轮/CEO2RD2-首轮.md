# CEO2-RD2-运行时 首轮盘点（内存 / ABI）

> **角色：CEO2-RD2-运行时（二司）**　**日期：2026-11-07**　**依据：董事会判决 v1.6.0 第 2.2、5 条**
> **域：`impl/runtime/**`（内存、ABI），规范面 S3 / S5 / S7**
> **模式：只读。** 未改生产代码、未 commit、未派工、未碰他人文件；本文件是唯一产出。
> **基线：主仓 `dfcf033`（`impl/runtime` 工作区干净，与 `wt/e5-runtime` 同内容）**
> **环境：Apple clang 17.0.0 (clang-1700.6.3.2) / x86_64-apple-darwin25.5.0 / Go 1.27.3**

---

## 0. 一句话结论

**六套件 6/6 绿、ABI 面 26 个符号齐、结构分层清楚；但绿是"单线程 + 不打 sanitizer + 不测句柄"的绿。**
实测确认 2 个未覆盖的 P0：**对 GC 对象调用 `xrt_release` 必崩**、**已正确 close 的句柄仍报"句柄泄漏"**；另有 1 个静态 P0（分配头不清零导致 UB）和 2 个悬空/泄漏级弱槽问题。**当前不具备"内存安全可验收"状态，只能声称"单线程逻辑断言通过"。**

---

## 1. 运行时结构

### 1.1 分层与文件（18 个 C/H + 1 脚本 + 1 文档，2409 行）

| 层 | 文件 | 行 | 职责 | 稳定性 |
|---|---|---:|---|---|
| **公开 ABI** | `xrt.h` | 112 | 唯一对外头：`xrt_*` 26 符号、`xrt_kind` / `xrt_type` / `xrt_string` / `xrt_weak_slot` / `xrt_handle` / `xrt_bytes` | **冻结**（S7 §6.1，变更走主版本） |
| | `xrt_abi.c` | 182 | 薄封装 → `rt_*`；句柄实现、任务根、屏障 | 冻结面实现 |
| **ARC 核心** | `rt.h` / `rt.c` | 112 / 138 | 分配头（64 B，8 对齐）、原子计数、retain/release、终结链、隔离区、fatal、String | 内部（不随 SDK 分发） |
| **GC** | `rt_gc.h` / `rt_gc.c` | 45 / 177 | 标记—清扫、GC 清单、ARC 扫描链、全局根 | 内部 |
| **弱表** | `rt_weak.c`（接口在 `rt.h`） | 70 | 目标侧链弱槽、终结前清除 | 内部 |
| **策略判定** | `rt_policy.h` / `rt_policy.c` | 51 / 55 | S2 §15.1 判定表执行器（纯函数） | 内部（输入结构冻结） |
| **XDK 原语** | `rt_std_runtime.c` / `rt_std_text.c` / `rt_std_sys.c` | 120 / 259 / 153 | `xdkc_*` 22 个：诊断/退出/时钟/env；parse/format/UTF/regex；文件/目录/存在性/子进程 | 供绑定层 |
| **测试** | `test_rt/gc/hard/abi/std/res.c` | 134/133/133/135/281/44 | 六套件 | — |
| **构建** | `build_rt.sh` | 23 | 六套件唯一入口 | — |

### 1.2 结构与不变量落点

- 对象 = `rt_header`(64 B) + 载荷；`rt_payload()` 是内部唯一偏移来源（`rt.h:27` 实现于 `rt.c:27`）。
- 分配两条路径：`rt.c:15 rt_alloc`（只给 String 用）与 `rt_gc.c:22 alloc_common`（给 `rt_arc_new` / `rt_gc_new` 用）。**两条路径初始化程度不同，见 G-01。**
- 终结链（S3 §14）：`terminated=1` → 清弱槽 → 扫描链注销 → `deinit(对象指针)` → 入隔离区（`rt.c:51-62`）；隔离区只在 `rt_gc_collect` / `xrt_safepoint` 释放（`rt.c:129-138`、`rt_gc.c:146-150`）。
- GC：根集合 = 全局根数组 + ARC 扫描链（`rt_gc.c:99-107`）；清扫时先 `release` ARC 引用再 `deinit` 再 `free`（`rt_gc.c:119-144`）。
- 根入口共 3 个但只有 1 个容器：`xrt_register_root` 与 `xrt_task_root_bind` 都写 `g_roots`（`xrt_abi.c:65-79`）。**任务根没有独立语义，见 G-05。**
- 线程模型：全库单线程。全局链/根数组/弱链均为普通全局变量（`rt_gc.c:14-18`、`rt_weak.c:14-18`），`terminated` / `marked` 非原子；S3 §11/§12 的并发切片未接。

### 1.3 公开 ABI 面实测清单（26 符号）

`xrt_alloc` `xrt_retain` `xrt_release` `xrt_refcount` `xrt_weak_bind` `xrt_weak_read` `xrt_weak_clear` `xrt_write_barrier` `xrt_register_root` `xrt_unregister_root` `xrt_safepoint` `xrt_task_root_bind` `xrt_task_root_unbind` `xrt_runtime_init` `xrt_string_new` `xrt_string_from_c` `xrt_string_alloc` `xrt_type_string_descriptor` `xrt_string_len` `xrt_string_bytes` `xrt_handle_new` `xrt_handle_native` `xrt_handle_close` `xrt_handle_mark_closed` `xrt_handle_is_closed` `xrt_fatal`

- `nm -gU /tmp/xnull_test_abi` 导出 `_xrt_*` = **26**，与头文件一致（无漏定义、无多导出）。
- `xrt_bytes`（`xrt.h:84-87`）**只有类型没有入口**，是死面（G-09）。
- 与 S3 §22 最小合同对照：分配/计数/弱表/根/安全点/任务根均有名；**`write_barrier` 签名与 S3 §22 的 `(obj, field, value)` 不一致**（G-07）。

### 1.4 交接件过时点（读旧件者注意）

| 来源 | 旧表述 | 当前事实 |
|---|---|---|
| `收件箱/CTO2/交接-E5E6-2026-11-07.md:11` | `xrt_task_root_*` 在 `test_abi.c` 零覆盖 | **已覆盖**：`test_abi.c:98-105` |
| `wt/e5-runtime/收件箱/E5/域盘点-2026-11-07.md:32` | 资源表用 `python3 ../tools/gen_resources.py` | 已改 `go run ./cmd/xnull dev res`（`build_rt.sh:20`，S0-21c）；`impl/tools/` 已不存在 |
| 同上 `:57-62` | 六套件产物大小/构建秒级 | 冷缓存实测 **94 s**（res 段触发 Go 编译），热缓存 12 s |
| `impl/docs/ffi-contract.md:112` | `xrt_handle` 完成、`test_abi.c` 覆盖 | **`test_abi.c` 对 `xrt_handle` 零引用**（`grep xrt_handle test_*.c` 无命中） |

---

## 2. 六套件

### 2.1 入口与基线

```
cd impl/runtime && sh build_rt.sh
```
`set -e`；统一 `cc -std=c11 -Wall -Wextra -Werror -O2`；产物只落 `/tmp/xnull_test_*`，**无 `.a`/`.dylib` 库产物**。

### 2.2 套件矩阵（本轮实测）

| # | 套件 | 链接源 | 断言 | 覆盖面 | 结果 |
|---:|---|---|---:|---|---|
| 1 | `test_rt` | rt.c rt_policy.c rt_gc.c rt_weak.c | 13 assert + 10 行判定表 | ARC 基础、判定表、确定性 | PASS |
| 2 | `test_gc` | rt.c rt_gc.c rt_weak.c | 13 assert | 不变量 2/3/5/6 | PASS |
| 3 | `test_hard` | rt.c rt_gc.c rt_weak.c | 12 assert | 复活检测、弱清除时序、槽位复用 | PASS |
| 4 | `test_abi` | + `xrt_abi.c` | 27 CHECK | 26 符号中的 20 个（未覆盖：`xrt_handle_*` 5 个 + `xrt_fatal`） | PASS |
| 5 | `test_std` | + `rt_std_*.c` | 74 CHECK / 9 子测试 | XDK 原语 | PASS |
| 6 | `test_res` | 现场生成 `res_table.c` | 9 CHECK | 资源表合同（升序/重名/二分） | PASS |

**本轮结果：6/6 PASS，0 失败、0 警告**；热缓存 `sh build_rt.sh` = **12.1 s**，冷缓存 **94.1 s**（差异全在 res 段 `go run`）。
输出：`ok policy table` / `rt tests passed` / `gc tests passed` / `hard-semantics tests passed` / `abi 测试通过` / `std 测试通过` / `资源表测试通过`。

### 2.3 覆盖空洞（六套件看不到的东西）

| 空洞 | 证据 |
|---|---|
| `xrt_handle_*` 全族 | `grep xrt_handle test_*.c` = 0；Go 侧 `internal/codegen/ffi/*_test.go` 联编 `xrt_abi.c` 但也不调用句柄 |
| GC 对象的误用路径（release/close/重复终结） | 无用例，`test_abi.c:85-105` 只走"根登记→collect"正路 |
| 弱槽在目标释放后的操作 | `test_abi.c:73-76` 故意先 clear 后 safepoint，**掩盖悬空** |
| 分配头未初始化字段 | 断言全部通过是因为对象走 `alloc_common`（有 memset），唯一走 `rt_alloc` 的 String 不检查头字段 |
| 并发（计数原子性、弱清除、根登记） | 无 pthread 用例；`grep pthread test_*.c` = 0；S3 §25 MEM-03/04 要求压力与并发 |
| 内存错误注入 | ASan 本机仍故障：`cc -fsanitize=address` 编 hello → 运行 **exit 132 (SIGILL)**；valgrind 未安装 → 无 UAF/UB 检测能力 |

---

## 3. 内存 / ABI 缺口（12 条）

> 严重度：**P0** = 已确认崩溃或静默 UB；**P1** = 合同不成立/资源无界；**P2** = 工程/文档面。
> "实测"= 本轮在 `/tmp` 用独立探针跑出；"静态"= 代码路径可判定，因 ASan 缺位无法实证。

### G-01（P0，静态）分配头未完整初始化 → 每次 String 终结都读未初始化字段

- 位置：`rt.c:15-25` 只写 `kind/type/refcount/terminated`；`marked/gc_next/scan_next/in_scan_list/weak_head` 五个字段未写。String 两处构造都走这条路径（`rt.c:84`、`rt.c:96`）。
- 触发：`rt_release(string)` → `rt_weak_clear_slots`（`rt.c:54` → `rt_weak.c:62-69`）读 `weak_head`；`rt_scan_unregister`（`rt.c:55` → `rt_gc.c:162-163`）读 `in_scan_list`。若 malloc 复用到曾挂弱槽/曾入扫描链的同尺寸块，`weak_head` 非空 → 按垃圾指针写 `s->cleared=1`（`rt_weak.c:68`）→ 段错误或静默写坏内存。
- 对照：`alloc_common` 先 `memset`（`rt_gc.c:27`），所以同类问题只在 String/`rt_alloc` 路径。
- 证据：静态。探针尝试"同尺寸块 0xAA 预填后释放再复用"未命中（macOS malloc 未复用该块），故**未能实证崩溃**，但读未初始化内存本身即 UB。
- 影响：ABI 层最常用的 String 类型全程走在 UB 上；未来任何在 String 上挂弱槽的 FFI 缓存场景直接踩雷。

### G-02（P0，实测崩溃）`xrt_release` 不区分 GC 对象 → 双重终结 + 悬空 `g_gc_list`

- 位置：`xrt.h:44-45` 对任意对象开放 `xrt_release`；`rt.c:51-62` 无条件走 ARC 终结链（清弱槽、deinit、入隔离区），但 GC 对象同时还在 `g_gc_list`（`rt_gc.c:32-40`）。
- 后果：`xrt_safepoint` 释放该内存（`rt.c:129-138`）后，`rt_gc_collect` 从悬空链表头继续遍历 → UAF/双重 free。
- 实测（探针，链接 `rt.c rt_gc.c rt_weak.c xrt_abi.c`）：

```
live before=1
deinit after release=1
EXIT=139            ← 在随后的 rt_gc_collect() 崩溃
```

- 规范：S3 §8/§14/§22——GC 对象生命周期由根集合与清扫决定，不得走 ARC 归零链。
- 影响：任何按"alloc/release 成对"直觉写绑定或生成代码的路径都会把进程打崩；FFI 层最易犯。

### G-03（P0，实测）句柄 deinit 回调基址错位 → 已正确关闭的句柄仍报泄漏

- 位置：`rt.c:57` 传给 `deinit` 的是**对象指针**；`xrt_abi.c:115-121 handle_deinit` 却按**载荷指针**解释（`handle_payload *p = payload;`）。同一文件里 `xrt_handle_is_closed` 用法是 `+ sizeof(rt_header)`（`xrt_abi.c:178`），两处自相矛盾即为证据。
- 实测：

```
xrt: 句柄泄漏：未显式 close（S7 §4.3）     ← 来自"已 close"的句柄
xrt: 句柄泄漏：未显式 close（S7 §4.3）     ← 来自"未 close"的句柄
closed(before)=0  close ret=0  closed(after)=1
```

- 后果：泄漏诊断恒假（读了 `kind`/`refcount` 当 `native`/`closed`），真正的原生泄漏无法发现；若未来 `handle_deinit` 触碰更远字段会越过 64 B 头进入错误偏移。
- 加成缺口：`xrt_handle_*` 在 C 六套件与 Go ffi 测试中**零用例**（§2.3）。

### G-04（P1，实测 UB）弱槽生命周期：清除只置标志，不摘链、不释放；目标释放后操作即悬空

- 位置：`rt_weak.c:62-69` 只 `s->cleared = 1`；槽位仍挂在 `target->hdr.weak_head` 上且不 `free`。目标在 safepoint 被释放后，槽位仍持 `s->target` 悬空指针。
- 触发：`xrt_weak_clear`（→`rt_weak_destroy`，`rt_weak.c:43-59`）会解引用 `s->target->hdr.weak_head`，此时目标内存已释放 → 释放后读；`xrt_weak_bind` 也不拒绝已终结/已释放目标（`rt_weak.c:20-34`）。
- 实测：目标 release + safepoint 后 `xrt_weak_read` 正确返回 NULL，随后 `xrt_weak_clear` **未崩溃但解引用了已释放内存**（本机 malloc 未回收页）；ASan 缺位无法定性。
- 泄漏面：调用方不显式 clear 的槽位永不释放（无目标终结时的批量回收路径）。
- 规范：S3 §16（清除后槽位必须可复用；并发清除与读取不得观察已终结目标）、MEM-04。

### G-05（P1）"任务根"没有任务语义：全局根集合上的幂等 set，多任务同绑会提前撤根

- 位置：`xrt_abi.c:77-79` 直接转 `rt_gc_root_add/remove`（`rt_gc.c:50-77`）；集合是"对象在/不在"，无计数、无任务归属。
- 后果：任务 A、B 绑同一 env，A 结束 `unbind` 即把 B 仍在用的 env 撤根 → 提前回收（S3 §11.1 / S7 §5.2 要求"任务存活期间保证可达"）；也无"注销后再被原生调用"的检测（FFI-05 部分态的原因之一）。
- 用例只覆盖单绑定（`test_abi.c:98-105`），故绿。
- 归属提示：真正的跨线程/所有权规则随调度器切片（`ffi-contract.md:143` 已声明），但**多绑定计数是 ABI 域可独立收口的部分**。

### G-06（P1）安全点不触发回收、无分配阈值 → 长跑内存无界

- 位置：`xrt_safepoint` 只 `rt_quarantine_flush()`（`xrt_abi.c:69-73`）；`rt_gc_collect` 只能显式调用（`rt_gc.c:146`）；无"分配字节数/次数阈值"状态。
- 后果：① 纯 ARC 程序的已终结对象停在隔离区，**不调用 safepoint 就永不释放**（`rt.c:59-61`）；② GC 对象只能靠调用方手动 collect；③ S3 §8"回收可以在分配点或安全点触发"未实现，MEM-03/MEM-09 的压力形态无从跑。
- 规范：S3 §8/§13；S5 §155（安全点必须覆盖任务挂起点）。

### G-07（P1）写屏障签名/语义不足，并发切片整体未接

- 位置：`xrt.h:56` 是 `xrt_write_barrier(void *obj)` 单参；S3 §22 要求 `write_barrier(obj, field, value)`。实现仅做 `terminated` 校验（`xrt_abi.c:57-63`），不维护 ARC 扫描链、不记录任何增量信息。
- 并发面：`rt.c` 用 C11 atomics 计数，但 `terminated`/`marked`/全部链表/根数组/弱链均为非原子（`rt_gc.c:14-18`、`rt_weak.c:14-18`）；S3 §11/§12 的"跨线程引用经发布点交换""写屏障覆盖扫描链维护"没有任何落点。
- 影响：当前只能声明"单线程顺序执行"；任何按 S3 §11 使用任务的程序不受保证，且文档未在 `xrt.h` 明示这一限制（只在 `.c` 注释里）。

### G-08（P1）ABI 合同面不完备：回调基址、`payload_size` 语义、布局一致性都没有机械验证

- `xrt.h` 未写 `deinit`/`scan` 收到的是**对象指针**（含 64 B 头），也未写 `payload_size` **不含头**；该约定只存在于内部 `rt.h:34-39`，而 `rt.h` 不随 SDK 分发 → 外部按字段名 `payload` 实现就错（`xrt_abi.c:115` 就是活样本）。
- `xrt_abi.c:28` 用强转对接 `xrt_type` ↔ `rt_type`，**无 `_Static_assert(sizeof/offsetof)`**；布局漂移只能等运行期崩。
- 无"A 独立编译单元只 include `xrt.h` + 只链 `xrt_abi.c`"的链接测试，也无符号清单/版本快照 → FFI-06（ABI 可链接、签名一致）目前**无法机械判定**，`status.tsv:34` 记"部分"是准确的。
- 相关：`rt_gc_new` 不校验 `scan != NULL`（`rt_gc.h:26` 只在注释要求），而 `mark_ref` 直接解引用 `type->scan`（`rt_gc.c:94`）→ 内部误用即空指针崩；`xrt_alloc` 有校验（`xrt_abi.c:30-33`），内部入口没有。

### G-09（P2）`xrt_bytes` 是死类型；缓冲区 pin 合同在 ABI 面无落点

- `xrt.h:84-87` 只声明 `struct { void *data; size_t len; }`，无任何入口；FFI emit 实际用 `(void*, size_t)` 对（`ffi-contract.md:124`）。S7 §3.4 / FFI-03 要求的"边界期间 pin、越界写可报告"在 C 侧没有挂点。
- 影响：要么补 pin 入口，要么按主版本流程删类型；现在两条都没走。

### G-10（P2，实测）初始化顺序合同不强制

- `xrt_runtime_init` 只置 `g_runtime_inited`（`xrt_abi.c:15-22`），无任何分配入口检查该标志；`xrt.h:10-11` 称"未初始化创建对象属调用方违约"但无检测。
- 实测：不调用 init 直接 `xrt_alloc` + `xrt_string_from_c` + release/safepoint，全部正常返回。

### G-11（P2）判定表行 1（singleton-gc）不可达

- `rt_policy.c:4-39` 无 singleton 分支，`rt_policy_rule_name` 却保留了行 1 名字（`rt_policy.c:44`）；输入结构 `rt_policy.h:37-46` 无对应字段。
- 规范：S2 §15.1 / MEM-01"每种输入得到正确策略"。当前行 1 只在名字上存在。

### G-12（P2）工程面：无库产物、无 sanitizer、res 段依赖 Go 工具链

- `build_rt.sh` 只产 `/tmp` 测试可执行，无 `.a`/`.dylib`、无 Makefile/CMake → 外部消费只能照抄 cc 命令行（与 `build.go:44-48` 的链接清单已出现漂移，见 §5）。
- ASan 本机 SIGILL 实测复现（exit 132），valgrind 未装 → **内存安全零检测**，所有 UAF/UB 结论只能靠静态判定。
- `build_rt.sh:20` 用 `go run ./cmd/xnull dev res`：冷缓存 **94 s**、热缓存 **12 s**；构建产物随 Go 缓存与网络/模块状态波动，CI 首次跑需预留 ≥120 s，且无预构建二进制兜底。

---

## 4. 前 3 张建议卡

> 卡号暂记 **建议 S1-31 / S1-32 / S1-33**，未占号；以 `收件箱/会话台账` 与 CEO2-PJ 分配为准。三卡都属 `impl/runtime/**`，主责建议 **CEO2-RD2**，需先建 worktree（v1.6.0 第 4.4 条）。三卡互不重叠写文件顺序：卡 1 改 `rt.c`+`xrt.h`+`xrt_abi.c`+`test_abi.c`；卡 2 改 `rt.c`+`rt_weak.c`+`xrt_abi.c`+新增 `test_abi_neg.c`；卡 3 改 `rt_gc.c`+`xrt_abi.c`+新增 `test_stress.c`（若并行，卡 2/3 顺延到卡 1 合并后开工，避免同文件双写）。

### 卡 1（P0）：分配头初始化统一 + 回调基址合同冻结 + 句柄修正

| 项 | 内容 |
|---|---|
| 目标 | 消除 G-01/G-03/G-08 的静默 UB 与错误诊断；把回调约定写进冻结 ABI 面 |
| 范围 | ① `rt_alloc` 与 `alloc_common` 合并为单一路径（统一 `memset` 头 + 计数从 1）；② `xrt.h` 明确 `deinit`/`scan` 收**对象指针**、`payload_size` 不含头，并给 `xrt_payload`-等价说明；③ `xrt_abi.c` 加 `_Static_assert`（`sizeof(xrt_type)==sizeof(rt_type)`、各字段 `offsetof` 一致）；④ 修 `handle_deinit` 按对象指针取载荷；⑤ `test_abi.c` 补 `xrt_handle_*` 5 个入口的用例（含"已 close 不得报泄漏"、重复 close、`native==NULL`） |
| 不做 | 不改终结链时序、不改 GC 语义、不做并发、不动 `rt_std_*` |
| 验收 | `sh build_rt.sh` 6/6；新增断言 ≥12；`xrt_handle_*` 覆盖率从 0 → 5/5；`grep -c xrt_handle test_abi.c` ≥ 10；句柄泄漏告警在"正确 close"路径下 **0 条** |
| 证据 | `evidence/<卡号>/` 六套件原始输出 + 句柄正/负向运行输出 |
| 风险 | `rt_alloc` 合并会动 String 分配路径，属 M3 已验收代码；需在卡内声明"零语义改写、只补初始化"，并保留 `test_rt/gc/hard/std` 全绿作回归 |

### 卡 2（P0）：ABI 生命周期防御矩阵（GC/已终结/弱槽）

| 项 | 内容 |
|---|---|
| 目标 | 把"误用必崩"改成"误用必 fatal"，并修掉弱槽悬空/泄漏（G-02/G-04/G-10） |
| 范围 | ① `xrt_release`/`xrt_retain` 校验 `kind`：GC 对象 → `rt_fatal`（给出规范条文）；② 已终结对象上 `release/close/weak_bind` 的行为矩阵入 `xrt.h`（fatal 或安全 no-op，逐条定案）；③ `rt_weak_clear_slots` 在目标终结时把槽位摘链并置 `target=NULL`，提供槽位批量释放/复用路径，`rt_weak_destroy` 对已终结目标安全；④ `xrt_weak_bind` 拒绝已终结/已释放目标；⑤ `xrt_runtime_init` 未调用时的分配行为按 ② 定案（建议 fatal 或显式 `xrt_runtime_inited()` 查询）；⑥ 新增 `test_abi_neg.c`（fatal 用可替换 handler 断言 reason 文本，沿用 `test_hard.c:83` 的模式） |
| 不做 | 不做跨线程原子 close（显式归调度器切片，`ffi-contract.md:143`）；不改 GC 标记算法 |
| 验收 | G-02 探针转为回归用例并 exit 0（不再 139）；GC release 断言 `rt_fatal` 被调用 1 次；弱槽"目标释放后 clear/read/bind"三路径全安全且槽位计数回到 0；六套件 6/6 不变 |
| 证据 | 负向用例输出（fatal reason 逐条）+ 探针前后对比 |
| 风险 | 弱槽摘链改动触碰不变量 4 的时序；必须保留 `test_hard.c` 的"deinit 内读弱槽为 NULL"断言不改 |

### 卡 3（P1）：回收触发与任务根计数（让"绿"覆盖长跑与多任务绑定）

| 项 | 内容 |
|---|---|
| 目标 | 消除 G-05/G-06 的"内存无界 + 提前撤根"，建立可压测基线 |
| 范围 | ① 分配路径记字节/次数，超阈值在安全点触发 `rt_gc_collect`（阈值可配置，默认值入文档）；② `xrt_safepoint` 语义定案：flush 隔离区 + 条件收集（保持"不会在任意位置隐式收集"的可预期性）；③ 任务根改为**引用计数/多重集**（同一对象被 N 个任务绑定，N 归零才撤根），保留 `xrt_register_root` 的幂等集合语义不变；④ 新增 `test_stress.c`：10⁵ 次 alloc/release 的常驻内存上限、GC 环压力、同 env 双绑/单撤的可达性断言 |
| 不做 | 不做线程、不做写屏障增量算法（G-07 归并发切片/CEO2-RD3）；不改 `xrt.h` 冻结签名 |
| 验收 | 压力用例常驻内存收敛（给出峰值上限断言）；双绑定场景：撤一个后对象仍存活、全撤后可回收；六套件 6/6（`test_stress` 为第 7 套件，`build_rt.sh` 追加且不改变六套件输出格式） |
| 证据 | 压力用例输出（峰值/回收次数）+ 双绑定可达性断言 |
| 风险 | 自动收集会改变现有用例对"何时 release/何时回收"的假设（如 `test_abi.c:66` 依赖显式 safepoint），阈值默认必须先关（0=关闭）再在压力套件内开启，避免打翻既有六套件 |

---

## 5. 跨域事实（只登记，不派工、不占卡）

1. **生成代码完全绕过稳定 ABI**：`internal/codegen` 生成文本 `#include "rt.h"`/`"rt_gc.h"`（`codegen.go:27-28`），结构体直接内嵌 `rt_header`（`classes.go:118`）、走 `rt_arc_new`（`classes.go:150`）、手写 `malloc` 建字符串头（`codegen.go:113`）；`build.go:44-48` 链接清单只有 `rt*.c`，**不含 `xrt_abi.c` 与 `rt_std_*.c`**。→ 当前任何 `xnull build` 产物都无法调用 `xrt_*`，FFI-06 无法真实成立（归代码生成域，E4 / CEO1-RD3）。
2. **`rt_std_*` 22 个 `xdkc_*` 只被 C 测试与 Go 联编覆盖**，XNull 层仅 `bindings/xdk/{runtime,sys}.xfb` 12 入口，text/env/proc 未绑定（归绑定/XDK 域，CEO2-RD3）。
3. **`status.tsv` 与实现分布不一致**：FFI-02/04/05/06/07 全"部分"，MEM-01/02"部分"；MEM-03/04/09/11 无行。→ 建议 CEO3 在卡 1–3 关闭时同步台账（不属本文件职责）。
4. **`impl/docs/ffi-contract.md:112` 的"`xrt_handle` 完成且 `test_abi.c` 覆盖"与事实不符**（§1.4），需文档更正。

---

## 6. 未验证事项（明确标注）

| 事项 | 状态 |
|---|---|
| G-01 是否能在真实复用场景崩溃 | **未实证**：探针未能让 malloc 复用 0xAA 块；ASan 本机 SIGILL、valgrind 未装。结论基于"读未初始化内存"的静态判定 |
| G-04 悬空访问是否必崩 | **未实证崩溃**（仅确认解引用了已释放内存），同因缺 sanitizer |
| 并发正确性 | **完全未验证**：无线程用例，代码注释自述单线程骨架 |
| 六套件在 Linux/CI 目标机上的结果 | **未验证**：本轮只在 macOS x86_64 + clang 17 跑过；`go run` 冷启动耗时也未在 CI 测过 |
| `xrt_abi.c` 在真实生成产物中的链接 | **当前不可达**（§5 第 1 条），故 ABI 的"可链接"只有测试进程内证据 |
