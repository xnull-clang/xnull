# CEO2-QA1 首轮验收清单（只读盘点）

> 角色：`CEO2-QA1-运行时`　域：内存 / 并发 / FFI 验收
> 依据：董事会判决 v1.6.0 第 2.2 条（二司编制）、第 5 条（首轮只读任务）
> 写入域：本文件（`收件箱/CEO2/**`）。**未改生产代码、未 commit、未派工、未碰他人文件。**
> 基线：主仓 `dfcf033`；Apple clang 17.0.0；本文编号 `QA2-*` 是验收侧自有编号，与规范 MEM-/TASK-/FFI- 编号的映射在每行「规范行」列。

---

## 0. 结论

1. **内存/FFI 有实现、基线全绿**：`bash impl/runtime/build_rt.sh` 退出 0（7 组 C 测试），`go test ./internal/codegen/ffi ./internal/interp` 均 ok（50.9s / 12.4s）。
2. **发现 4 个 P0 候选，其中 3 个已实测复现**：堆头未全量初始化（普通 String release 即可 SIGSEGV）、错 kind 终结（GC 对象走 ARC release 后 collect 崩）、隔离区无分配点回收（20 万次 churn 峰值 20.2 MB vs 1.85 MB）。第 4 个（弱槽位跨目标回收）静态可证，需 ASan 环境闭环。
3. **并发域零实现**：`xdk.tasks` / `xdk.sync` 只在 sema 登记符号（`impl/internal/sema/xdk.go:38-41`），codegen/interp 无任何派发；台账 S5 九行全「未实现」。本清单对并发只给判据与门禁，不给 PASS。
4. **台账口径有冲突**：S3 的 MEM-03/04/08 标「未实现、用例文件空」，但 `impl/runtime/test_gc.c`、`test_hard.c` 已覆盖其中多项；status.tsv 却只把它们挂在 S2 的 MEM-02 名下。整体改 PASS 是虚报，维持未实现是低估，须逐子项重锚（§5）。

---

## 1. 基线实测（本轮亲跑）

| 项 | 命令 | 结果 |
|---|---|---|
| 运行时 C 测试 | `bash impl/runtime/build_rt.sh` | 退出 0；`rt / gc / hard / abi / std / 资源表` 全通过（`-Wall -Wextra -Werror -O2`） |
| FFI 包测试 | `go test ./internal/codegen/ffi -count=1` | `ok 50.947s` |
| 解释器测试 | `go test ./internal/interp -count=1` | `ok 12.430s` |
| ASan 可用性 | 任意程序 `-fsanitize=address` 编译运行 | 空输出、异常退出；与 `impl/runtime/README.md`「本机 ASan 环境故障」一致 → 越界类负例本轮只能静态证明 |

复核锚点：`impl/runtime/build_rt.sh:5-14`；`impl/runtime/README.md` 环境备注；`impl/internal/codegen/ffi/ffi_test.go:175`；`impl/internal/interp/interp_test.go:28`。

---

## 2. 清单总表（22 条）

级别：**P0** = 阻塞正确性/可导致 UB 或假绿；**P1** = 合同缺口，需排期；**P2** = 加固/口径。
状态：**PASS** = 达标；**部分** = 有实现有覆盖但判据不全；**FAIL** = 已复现不达标；**未实现** = 域内无实现。

### A. 内存（终结 / 泄漏 / 复活）

| ID | 规范行 | 判据（通过条件） | 负例必须断言 | 证据锚点 | 状态 |
|---|---|---|---|---|---|
| QA2-M01 | S3 §2 | 任何构造路径返回的对象，`hdr` 九个字段（kind/type/refcount/terminated/marked/gc_next/scan_next/in_scan_list/weak_head）全部为确定值 | `MallocScribble=1` 下 `rt_string_from_c` → `rt_release` 不崩溃；头字段为 0/NULL | `rt.c:15-25` 只写 4 个字段；`rt_gc.c:22-42` 有 memset | **FAIL（P0，§3.1）** |
| QA2-M02 | S3 §16 | 目标被隔离区回收后，弱槽位仍可 read（NULL）与 clear（安全析构），不得访问目标已释放内存 | release → safepoint → weak_clear | `rt_weak.c:48` 读 `target->hdr.weak_head`；`rt_weak.c:62-69` 只置 cleared 不摘链 | **FAIL（P0，静态，§3.4）** |
| QA2-M03 | S3 §14 | deinit 内可观测：`refcount==0`、弱槽已清、`in_scan_list==0`、对象未 free；顺序固定 | deinit 内四项断言，任一不满足即 fatal | `rt.c:51-61`；`test_hard.c:41-46` 只验弱一项 | 部分 |
| QA2-M04 | S3 §14/§15 | 复活三路径全终止：①ARC deinit 存 self 后 retain；②对 terminated release 不递减；③GC 清扫 deinit 存 self 并试图再入根 | 三路径各一进程级用例，断言 fatal 原因串与退出码 | `rt.c:29-37`；`test_hard.c:88-101`；`rt_gc.c:134-140`（GC 路径无复活检测） | 部分（③缺） |
| QA2-M05 | S3 §7 | `rt_release/rt_retain` 只接受 ARC；对 GC 对象必须 fatal，不得入隔离区、不得破坏 `g_gc_list` | GC 对象走 `xrt_release` → 期望 fatal | `rt.c:43-62` 无 kind 分支；`rt_gc.c:119-144` 依赖链表完整 | **FAIL（P0，§3.2）** |
| QA2-M06 | S3 §12/§13 | 分配点是安全点：分配路径按阈值/间隔 flush 隔离区；churn 场景峰值 RSS 有界 | 20 万次 create/release 不显式 safepoint，峰值不超过周期 safepoint 的 2× | `rt_gc.c:22-42`、`rt.c:15-25` 无 flush；`rt_gc.c:146-150` 仅显式 collect | **FAIL（P0，§3.3）** |
| QA2-M07 | S2 §15.6 / S3 §8 | 六条不变量逐条映射用例 ID；10⁵ 对象压力下无泄漏、无悬挂、无重复释放 | 环×根×扫描链×清扫交错；ASan/guard 零报告 | `test_gc.c:62-133`（覆盖 2/3/5/6，无压力、无 1/4 单列） | 部分 |
| QA2-M08 | S3 §10 | 容器与字符串布局符合 §10；纯值元素区免扫描；`clear/remove` 对 ARC 元素立即 release | 标量数组 scan 不得进入元素区；clear 后 refcount 归零 | 运行时只有字符串类型；interp 容器走 Go（`values.go:16-56`） | 未实现 |

### B. 并发 / 取消 / 同步

| ID | 规范行 | 判据（通过条件） | 负例必须断言 | 证据锚点 | 状态 |
|---|---|---|---|---|---|
| QA2-C01 | S5 §9、红线 2 | 未实现前任何产物不得声称并发可用；使用任务 API 必须在编译期或运行期显式失败并标注归属切片 | `import xdk.tasks` + 使用 → 单一、可 grep 的「不支持 + 归属切片」诊断，不得落进通用错误 | `sema/xdk.go:38-41` 仅登记符号；`multifile.go:76` 仅跳过 `xdk.*`；`interp.go:657/947` 文案无切片归属 | 未实现 + 失败点不统一（P1） |
| QA2-C02 | S5 CANCEL-01 | 组取消向下传播；`checkCancel` 返回 `Err(CancelledError)`、`kind=Cancelled`；无检查点任务在 close 时仍被等待 | 任务吞掉取消继续跑 → close 必须等其终结，不得提前返回 | 无实现 | 未实现 |
| QA2-C03 | S5 CANCEL-02 | 取消后 `defer/errdefer` 完整执行；清理期间到达的取消排队不丢 | 清理体内再 cancel → 清理不中断、取消不丢失 | defer LIFO 已有（`hard_test.go:33-127`），无取消维度 | 未实现 |
| QA2-C04 | S5 TASK-02 | `close` = 取消 + 等待全部终结（含清理完成），返回首个非取消错误；未关组退出作用域为编译错误 | 漏 close 的组必须编译失败 | 无实现 | 未实现 |
| QA2-C05 | S5 TIMEOUT-01 | `joinDeadline` 超时返回 `Err(Timeout)` 且不自动取消；`withDeadline` 到期 → `Cancelled`；不早于到期点 | 超时后任务仍继续并最终交付业务结果 | 无实现 | 未实现 |
| QA2-C06 | S5 SYNC-01/02/03 | `Mutex<struct>` 拒绝、`withLock` 作用域化、锁内 Guard 逃逸拒绝；`Channel` 关闭终态确定且可取消；Atomic 顺序一致；retain/release 多线程压测 deinit 恰一次 | 并发 8 线程 retain/release，终值 0、deinit 计数 1 | 实现全无；且 `rt_gc.c:14-18`、`rt_weak.c:20-59` 全局链表/槽位非原子 → 多线程 alloc/collect 必竞态 | 未实现 + 并发安全前置未定（P0 设计项） |

### C. FFI / ABI

| ID | 规范行 | 判据（通过条件） | 负例必须断言 | 证据锚点 | 状态 |
|---|---|---|---|---|---|
| QA2-F01 | S7 §10 FFI-01/03 | FFI-100..111 每条有负例且断言**具体诊断码**，不许只断言「有错」 | 12 类各一 | `ffi_test.go:175-345` | **PASS**（本轮复跑） |
| QA2-F02 | S7 §10 FFI-02 | `layout(c)` 的 sizeof、每字段 offsetof、对齐与 C 基准一致；同尺寸不同布局必须拒绝 | C 侧交换两个同宽字段（总尺寸不变）→ 期望 fatal | `emit.go:262-276` 只比 sizeof；台账 FFI-02=部分 | 部分（P1） |
| QA2-F03 | S7 §7.1/INV-FFI-2/3 | 未知码 → `Internal`（非 Ok）；取消/超时不降级 `Internal`；非零码不静默吞 | 原生返回未声明码 → `Internal`；取消路径错误码 → `Cancelled` | `emit.go:281-287` 只覆盖生成面；运行期只测已知码 | 部分 |
| QA2-F04 | S7 §3.2/§4.4/§9 | Bool 返回非 0/1 → fatal；canary 越界写 → fatal；**错误码非零时 canary_leave 仍执行** | 越界 1 字节、Bool 返回 2、错误码路径越界三例 | `emit.go:29-55`、`:334-336`（postAlways） | 部分（负例运行缺） |
| QA2-F05 | S7 §4.3/INV-FFI-9 | 重复 close 幂等且不触达原生；关闭后 read → fatal；close 入口对已关闭返回 0；deinit 不 close 只诊断 | close→close→read 三连；deinit 路径句柄泄漏仅告警 | `xrt_abi.c:115-180`；`emit.go:366-380`；FFI 层 `xdk_test.go:138-180`；**`test_abi.c` 零句柄覆盖** | 部分（运行时层缺单测） |
| QA2-F06 | S7 §6.1/INV-FFI-7 | 只 `#include "xrt.h"` 的 clean-room 消费者可编译链接；`xnull build` 产物含 `xrt_abi.c` 与 import 闭包内 `rt_std_*.c` | 消费 `xrt_string_new` 的产物必须链接成功；缺符号必须链接期显式失败 | `build.go:44-48` 仅 `rt.c/rt_gc.c/rt_policy.c/rt_weak.c`；`xrt.h:1-12` 声称唯一对外面 | **FAIL（P0，§3.6）** |
| QA2-F07 | S7 §5.2/INV-FFI-6 | `EmitTrampoline` 显式 `ErrTrampolineReserved`；注销后调用检测；回调内 panic 终止；跨任务句柄规则未实现不得宣称 | 预留接口不产出任何代码 | `emit_test.go:299-317`；`ffi-contract.md:138-143` | 预留 PASS；其余未实现 |
| QA2-F08 | S7 §6.1/§6.3 | `xrt_runtime_init` 前创建对象必须 fatal；空指针访问器行为合同化（fatal 或明确值），不得段错误 | 未 init 直接 alloc；`xrt_string_len(NULL)` | `xrt.h:10-12/68`；`xrt_abi.c:17-37` 无 init 校验；`xrt_abi.c:91-93` 直接解引用 | **FAIL（P1，§3.5）** |

---

## 3. P0 复现（本轮亲测）

> 探针在 `$TMPDIR/qa1probe` 编译，源文件只复制 `impl/runtime/*`，**未写入仓库**。以下代码可直接粘贴复跑。

### 3.1 堆头未全量初始化（QA2-M01）

`rt.c` 的 `rt_alloc` 只写 4 个字段，`weak_head/marked/gc_next/scan_next/in_scan_list` 保留 malloc 原值；`rt_release` 无条件调 `rt_weak_clear_slots`，直接沿垃圾 `weak_head` 走链。

```c
#include "rt.h"
#include <stdio.h>
int main(void){
  rt_string *s = rt_string_from_c("abc");
  printf("weak_head=%p marked=%d in_scan=%d\n",
         (void*)s->hdr.weak_head, s->hdr.marked, s->hdr.in_scan_list);
  rt_release(s);
  printf("released\n");
  return 0;
}
```

```
cc -std=c11 -O0 -g -o p1 p1.c rt.c rt_gc.c rt_weak.c xrt_abi.c
./p1                              # weak_head=0x0        → 退出 0（掩盖）
MallocScribble=1 ./p1             # weak_head=0xaaaa...  → SIGSEGV，退出 139
```

结论：所有 XNull `String` 走这条路径。当前「全绿」只是因为新分配内存恰好为零；堆复用后是确定性崩溃。**修法方向（不派工，仅记）**：`rt_alloc` 与 `alloc_common` 共用同一初始化函数，或统一走 `memset`。

### 3.2 错 kind 终结（QA2-M05）

```c
#include "rt.h"
#include "rt_gc.h"
#include "xrt.h"
#include <stdio.h>
typedef struct { rt_header hdr; } node_t;
static void deinit(void *p){ (void)p; }
static void scan(void *p, void (*v)(void*)){ (void)p; (void)v; }
static const rt_type T = {"N", sizeof(node_t)-sizeof(rt_header), deinit, scan};
int main(void){
  node_t *g = rt_gc_new(&T);
  rt_release(g);      /* GC 对象被当作 ARC：置 terminated + 入隔离区 */
  xrt_safepoint();    /* 隔离区 free，但 g 仍在 g_gc_list */
  printf("live=%zu\n", rt_gc_live());
  rt_gc_collect();    /* 遍历已释放节点 → UAF */
  return 0;
}
```

实测：`live=1` 后 `rt_gc_collect()` 段错误，退出 139。合同要求：错 kind 必须 fatal，且不得污染 GC 清单。

### 3.3 隔离区无分配点回收（QA2-M06）

```c
for (int i=0;i<200000;i++){
  rt_string *s = rt_string_from_c("0123456789");
  rt_release(s);                       /* 每次进隔离区，无人 flush */
}
printf("done\n");
```

| 场景 | 峰值 RSS |
|---|---|
| 不显式 safepoint | **20,168,704 B（20.2 MB）** |
| 每 1000 次 `xrt_safepoint()` | 1,847,296 B（1.85 MB） |

10.9× 线性增长。S3 §12 要求「安全点必须覆盖分配点」，当前分配路径无 flush/阈值/触发。长驻进程的 churn 场景等同泄漏（直到进程退出）。

### 3.4 弱槽位跨目标回收（QA2-M02，静态）

`rt_weak_clear_slots` 只把槽位 `cleared=1`，不把槽位从目标侧链摘除，也不清 `slot->target`；目标内存经隔离区 free 后，`rt_weak_destroy`（`rt_weak.c:48`）仍读 `s->target->hdr.weak_head` → UAF。`rt_weak_get` 因 `cleared` 先判而侥幸安全，destroy 没有这道短路。

本轮未能运行级复现：本机 ASan 不可用（§1），普通分配器下读已释放页不必然崩。需纳入「有 ASan/valgrind 的环境」闭环，判据见总表。修法方向：clear 时把槽位从目标侧链摘下并置 `slot->target=NULL`，destroy 对 `target==NULL` 直接 free。

### 3.5 ABI 前置条件（QA2-F08）

```c
void *o = xrt_alloc(XRT_KIND_ARC, &T);   /* 未调 xrt_runtime_init */
printf("alloc_before_init=%s\n", o ? "succeeded" : "null");
(void)xrt_string_len(NULL);
```

实测：`alloc_before_init=succeeded`（`xrt.h:10-12` 合同要求拒绝，实现无校验）；随后 `xrt_string_len(NULL)` 段错误退出 139（非 fatal、无诊断）。

### 3.6 构建清单不含 ABI 层（QA2-F06）

`impl/internal/codegen/build.go:44-48` 的 cc 参数只含 `rt.c / rt_gc.c / rt_policy.c / rt_weak.c`，不含 `xrt_abi.c`，也不含 `rt_std_*.c`。任何生成 `xrt_*` 调用的产物（P-08 迁移、P-09 包装）都必然链接失败。FFI 测试之所以通过，是测试自己手写了完整源码清单（`xdk_test.go:155-162`）——**测试绿不等于产物绿**，属典型假绿面。

---

## 4. 逐条判据补充（易踩空处）

- **QA2-M03/M04 的负例必须是进程级**：`rt_fatal` 在测试里装了 handler（`test_hard.c:83-86`），handler 只 longjmp，不终止进程。验收要另建一个不装 handler 的子进程，断言退出码（abort）与 stderr 片段，否则「终止进程」这条永远测不到。
- **QA2-M07 的六条不变量要编号到用例**：不变量 1（无悬挂）、4（弱表不阻止回收）目前在 `test_gc.c` 没有单列断言；不变量 4 只在 `test_hard.c:111-118` 覆盖。禁止用「gc tests passed」一行代表六条。
- **QA2-C06 的前置设计问题**：`rt_gc.c:14-18` 的 `g_gc_list/g_scan_list/g_roots` 与 `rt_weak.c` 的槽位链表全部无锁无非原子保护。S5 任务一旦真跨线程，第一件事不是写 API，而是决定「单线程合同」还是「加锁/线程本地堆」。这条不裁决，S5 验收无法启动。
- **QA2-F04 的错误路径**：`canary_leave` 在 `postAlways`（`emit.go:336`）是正确的，但必须用「原生返回非零 + 越界」的组合负例验证它真的执行；只测成功路径等于没测。
- **QA2-F05 的运行时缺测**：FFI 生成层测了句柄，`impl/runtime/test_abi.c` 对 `xrt_handle_*` 零覆盖（grep 无命中）。`xrt_handle_close` 的幂等、`mark_closed` 后再取 native、deinit 告警三条要在 C 层单独立测。
- **双路径边界**：解释器明确不模拟 ARC/deinit（`impl/internal/interp/objects.go:4`）。因此 MEM-03/MEM-08 这类时序用例只能跑 codegen 路径；台账与门禁必须写明「解释器豁免及理由」，不能悄悄只测一侧（红线 3 的例外必须留痕）。

---

## 5. 台账口径（不许两头虚报）

| 事实 | 台账/旁表现状 | 风险 |
|---|---|---|
| `impl/runtime/test_gc.c` + `test_hard.c` 已覆盖混合图、弱引用、复活、阻断回收 | `status.tsv:27` 把它们挂在 **S2 MEM-02 = 部分** | S3 的 MEM-03/04/08 显示「未实现、用例文件空」（台账 63-69 行） |
| 同一批 C 测试确实覆盖 S3 §8/§14/§15/§16 的部分判据 | S3 行没有任何用例文件 | 直接改 PASS = 虚报（缺压力、缺负例、缺 GC 复活路径）；维持未实现 = 低估 |
| FFI-01/03 = PASS，其余部分 | 与本文 QA2-F01/F03..F07 一致 | 无冲突 |

**建议口径（提交 CEO2，不自行改台账）**：按「不变量/时序/负例」拆成子锚点后重挂，例如 MEM-03 ← `test_gc.c` 不变量 2/3/5/6 + 新增压力用例；MEM-04 ← `test_hard.c` 弱时序 + 新增并发清除用例（当前无并发）；MEM-08 ← `test_hard.c` 复活 + 新增 GC 清扫复活负例。拆完再定状态，禁止整行改 PASS。

---

## 6. 本轮边界（明确不做/不能做）

1. **未跑 CI**：`ci/` 在 `wt/e6-toolchain`，未合 main；本轮只跑运行时脚本与两个 Go 包，不代表全量门禁。
2. **未做性能基线**：RSS 数字只作泄漏对照，不构成性能结论（归 QA2-性能）。
3. **并发全部不可执行**：无 `xdk.tasks`/`xdk.sync` 实现，C02–C06 只有判据，没有 PASS 结论。
4. **ASan/valgrind 不可用**：越界与 UAF 类负例（M02、M07 的悬挂部分、F04 越界）本轮只能静态定位；换环境后必须补跑。
5. **未覆盖 codegen 产物路径**：P-09/P-10 未落地，FFI 只验到生成文本与手写清单；产物级链路（`xnull build` + FFI 调用）属待验。
6. **未评判既有门禁**：S1-22、S0-04b 等属 CEO1/董事会口径，本文不重复、不对签。

---

## 7. 需 CEO2 一次裁决的事项

1. **台账重锚**：MEM-03/04/08 按子锚点拆分重挂，还是维持「未实现」直到补压力/负例？谁签这个口径（PJ / CEO1）？
2. **P0 修复归属**：M01/M02/M05（`rt.c`/`rt_weak.c`）落 RD2 还是 RD3？M06 的隔离区阈值落 RD2 还是 RD1？本文只标入口，不派工。
3. **S5 启动前置**：先写死「运行时单线程」合同（并在 ABI 层加线程断言），还是直接给 `g_gc_list`/弱表加锁？这决定 C06 能否立项。
4. **测试环境**：是否提供可用 ASan/valgrind 环境；没有的话 M02 与越界负例无法闭环，只能以静态审查结案。
5. **构建清单**：F06（`build.go` 不含 `xrt_abi.c`）是否随 P-10 一批切换；若继续延后，是否需要一条显式「产物不支持 xrt_*」的门禁断言，避免被误判为已支持。
