# 回执：S2-E5-weak（弱槽位目标死亡后的 UAF）

- 卡片：S2-E5-weak
- 执行位：运行时线 E5
- 结论：**完成**（先红后绿），commit `9e6de30`
- 证据：`evidence/S2-E5/{red.log,green.log,summary.md}`

## 交付

| 项 | 内容 |
|---|---|
| 根因 | `rt_weak_clear_slots` 只置 `cleared=1`，不清 `target`；目标经隔离区/GC `free` 后，`rt_weak_destroy` 仍遍历 `s->target->hdr.weak_head` → UAF |
| 修复 | clear：槽位 `target=NULL` + 目标 `weak_head=NULL`；destroy：仅存活且未清除才摘链，否则直接释放；get：`cleared || target==NULL` 返回 NULL |
| 诊断 | `rt.h` 增 `rt_weak_is_detached`（内部测试面，不进 `xrt.h` 公开 ABI） |
| 测试 | `test_hard.c` 第 5 段：release → `rt_quarantine_flush()` → 断言已解绑 → destroy 安全 |

## 先红后绿

- 红：`build_rt.sh` exit 134，`Assertion failed: (rt_weak_is_detached(s3)), test_hard.c:126`（`red.log`）。
- 绿：`build_rt.sh` exit 0，六套件全过（`green.log`）。
- 回归：`go test ./internal/codegen/... -count=1` 全绿；生成程序抽检（类/句柄）运行正常。

## 与 E4 的 deinit 发射对齐（契约，已发 E4）

1. 字段赋值（所有引用字段：类引用/String/容器/handle/Bytes）：求值 → retain 新值 → release 旧值 → 写入；禁止裸赋值。
2. `deinit` 发射顺序：用户 `deinit` 体（静态派发）→ 父类链（`super.deinit()` 显式接管则不自动重复）→ 释放仍非空的引用字段。
3. 字段释放覆盖 `xrt_handle *`、`xrt_bytes_obj *`（当前 `classField` 只标 String/容器/类引用）；句柄仍须显式 close，deinit 只释放句柄对象。
4. 弱槽位在 deinit 前已由运行时清除（本卡保证）；deinit 内读到弱引用必为 NULL。
5. 禁止 deinit 发布 self（静止检查由 E2 补）；运行时仅兜底「retain 已终结对象 → fatal」。

E5 未改 `internal/codegen/**`；以上由 E4 实现，冲突面为零。

## 后置（按指令）

- S2-E5-02/03：内存策略消费、GC 根登记与收集触发。
- S2-E5-11：弱槽位复用池。
- S2-E5-07：类描述符 `payload_size` 布局统一。

## 验收

```bash
cd impl/runtime && sh build_rt.sh
cd impl && go test ./internal/codegen/... -count=1
```
