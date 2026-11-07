# S2-E5-MEM01：对象生命周期（MEM-01 / MEM-02）运行时侧

- 卡片：MEM-01（deinit 顺序、stack 提升、struct 不进 ARC/GC）+ MEM-02（ARC↔GC、弱引用、环）
- 依据：S2 §6.4/§15.8、S3 §8/§14/§15/§15.6/§16
- 基线：`main=fa6d821`（分支 `pod/e5-runtime`，未自行合并 main）
- 结论：**运行时核心通过**；codegen 策略消费见下一卡 BND-10

## 先红（修复前）

GC 清扫顺序原为「scan 释放 ARC 引用 → deinit」，deinit 内字段已被释放，违反
S2 §6.4「deinit 执行时字段仍然有效」。`test_gc.c` 第 6 段断言 deinit 内
`rt_refcount(字段) == 2`：

```
Assertion failed: (g_gcv_seen_refcount == 2), function main, file test_gc.c, line 162.
EXIT=134
```

原始输出：`red-sweep-order.log`。

## 修复

`impl/runtime/rt_gc.c` 清扫顺序改为：

1. 置 `terminated`（防复活）
2. 清除弱槽位（S3 §14.1）
3. **调用 deinit（字段仍有效）**
4. `scan(sweep_release_arc_ref)` 释放 GC 对象持有的 ARC 引用（不变量 3）
5. `free`

`test_gc.c` 的 `gnode_deinit` 不再把字段置 NULL（置 NULL 等于放弃释放，与 §6.4
「置 null 提前释放」需要显式 release 的口径一致）；新增第 6 段验证字段有效性。

## 后绿

`green-build_rt.log`：六套件全过（rt/gc/hard/abi/std/res）。
`mem01-tests.log`：`TestS2MEM*` 4 例 PASS。

## MEM-01 覆盖

| 项 | 结果 | 说明 |
|---|---|---|
| deinit 顺序（用户体 → 字段释放；父类链） | **PASS** | `TestS2MEM01DeinitOrderBaseChain`：`main` → `base-deinit`；派生类自定义 deinit 被 sema `TY-203` 拒绝（S2 §6.4 允许派生 deinit，需 E2 修，见缺口） |
| stack 提升 | **判定就绪 / 未分配栈** | `TestS2MEM01StackPolicyClassification`：纯值类 `stackEligible=true policy=arc`，有 deinit 类 `stackEligible=false`。实际栈分配未做（§2.7 是「可以」的优化，不改变语义），列为后续 |
| struct 不进 ARC/GC | **PASS（拒绝面）** | sema 拒绝引用字段（§3.2）；codegen 对 `StructDecl` 显式报错、不分配堆对象（`TestS2MEM01StructNotInARCGC`）。struct 端到端代码生成未实现，属 E4 |

## MEM-02 覆盖

| 项 | 结果 | 证据 |
|---|---|---|
| GC 对象持 ARC 引用不悬挂/不泄漏 | **PASS** | `test_gc.c` 第 4/6 段：清扫恰好 release 一次；deinit 内字段有效 |
| ARC 持 GC 引用为根（不变量 2） | **PASS** | `test_gc.c` 第 3/5 段：扫描链 + 根双路可达 |
| 弱引用 deinit 前清除 | **PASS** | `test_hard.c`（ARC/GC 两链）+ 上一卡 UAF 修复 |
| 环由 GC 回收（运行时） | **PASS** | `test_gc.c` 第 1/2 段：无根环一轮回收；有根环存活 |
| 全 ARC 环的规避（判定面） | **PASS（判定）** | `TestS2MEM02CycleClassIsGCByPolicy`：直接字段环 → `policy=gc`；实际分配见 BND-10 |

## 已知缺口（不在本卡）

1. **派生类自定义 deinit** 被 sema `TY-203` 当同签名覆写拒绝（S2 §6.4 要求允许并自动串父链）→ E2。
2. **stack 分配**未实现（仅判定与语义验证）→ 后续卡。
3. **容器中介的引用环**（`List<Node>` 自引用）未被策略识别为环 → sema `classRefCycle` 只走直接类字段（E2）；当前保持 ARC，可能泄漏。
4. struct 端到端代码生成未实现 → E4。

## 复现

```bash
cd impl/runtime && sh build_rt.sh
cd impl && go test ./internal/codegen/ -run 'TestS2MEM' -count=1 -v
```
