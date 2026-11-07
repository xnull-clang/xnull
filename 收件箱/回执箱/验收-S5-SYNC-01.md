# 验收：S5-SYNC-01（Mutex）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `6c0609b`（含 S5-03 `63d15e6` 同步原语）
> **时间**：2026-11-08
> **证据**：`evidence/S5-QA/SYNC-01/`
> **依据**：S5 §7、SYNC-01；S5-03 E5 回执
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `Mutex.withLock` 作用域化 | **PASS**：`test_mutex`：hits=1，value 5→6 |
| 数据携锁与引用计数 | **PASS**：mutex 持 data +1；释放后 data 归零、deinit=1 |
| `Mutex<struct>` 拒绝 | **PASS**：`TestS5SyncTypeRules` → `TY-227`/同步规则 |
| 锁内再次 `withLock` 拒绝 | **PASS**：`TestS5ChannelAndMutexFlow` |
| 锁内逃逸 Guard | **PASS（设计）**：API 用回调作用域，无 Guard 可逃逸 |

**判定：PASS。** Mutex 运行时作用域化与数据所有权成立；sema 拒绝 struct 载荷与嵌套锁。

---

## 二、实测

```text
$ sh impl/runtime/build_rt.sh
...
sync tests passed (channel/mutex/atomic/cancel)
exit 0
```

`test_mutex`：`xrt_mutex_with_lock` 回调内 `b->value += 1`、`hits=1`；释放 mutex 后 data 引用归零，`g_box_deinit=1`。

sema：`Mutex<S>`（S 为 struct）→ `TY-227`；嵌套 `m.withLock(... withLock ...)` → 拒绝。

---

## 三、证据

- `evidence/S5-QA/SYNC-01/matrix.tsv`
- `runtime-build.log`（sync tests passed）
- `sema.log`（TestS5SyncTypeRules / TestS5ChannelAndMutexFlow）
- `收件箱/回执箱/回执-S5-03-E5.md`
