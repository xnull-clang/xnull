# S2-E5-weak：弱槽位目标死亡后 UAF 修复（先红后绿）

- 卡片：S2-E5-weak（S2 审计 S2-E5-06；runtime 线首卡）
- 契约：S3 §16（弱表不阻止回收；清除后的槽位必须可复用；禁止观察已终结目标）、S2 §6.4（弱引用在 deinit 前清除）
- 根因：`rt_weak_clear_slots` 只置 `cleared=1`，不清 `target`；目标经隔离区/GC `free` 后，
  `rt_weak_destroy` 仍以 `s->target->hdr.weak_head` 为起点遍历侧链 → 解引用已释放内存。

## 先红（修复前）

`test_hard.c` 新增第 5 段：目标 release → `rt_quarantine_flush()`（内存已释放）→
断言 `rt_weak_is_detached(s)`。修复前 target 仍悬空：

```
Assertion failed: (rt_weak_is_detached(s3)), function main, file test_hard.c, line 126.
build_rt.sh: line 10: ... Abort trap: 6
```

原始输出：`red.log`（build_rt exit 134）。

## 修复

`impl/runtime/rt_weak.c`：

1. `rt_weak_clear_slots(target)`：逐个 `s->cleared=1; s->target=NULL`，并把
   `o->hdr.weak_head=NULL`（侧链与目标一起失效）。
2. `rt_weak_destroy(s)`：仅当 `!cleared && target != NULL` 才从目标侧链摘除；
   已清除槽位直接释放，不再触达目标内存。
3. `rt_weak_get(s)`：`cleared || target == NULL` 即返回 NULL（不再读目标头）。

`impl/runtime/rt.h`：新增内部诊断 `rt_weak_is_detached`（测试用，不进 `xrt.h` 公开 ABI）。

## 后绿

```
ok  weak slot detached after target death
ok  weak slots (invariant 4, cleared before deinit, reusable)
hard-semantics tests passed
abi 测试通过 / std 测试通过 / 资源表测试通过
```

原始输出：`green.log`（build_rt exit 0）。

## 回归

- `sh impl/runtime/build_rt.sh` 六套件 exit 0。
- `go test ./internal/codegen/... -count=1` 绿（运行时改动不触发生成面回归）。
- 生成程序抽检：类/句柄/弱相关用例运行正常（`fh` 的「句柄泄漏」为预期的未显式 close 诊断）。

## 未做（按指令后置）

- 内存策略消费（BND-10/MEM-01）、GC 根登记与收集触发（S2-E5-02/03）。
- deinit 发射（S2-E5-01/04/05）属 E4 codegen；本卡只与 E4 对齐契约，不改 `internal/codegen/**`。
