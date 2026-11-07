# 验收：S4-CANCEL-02（取消清理路径）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `87c2053`（含 E5 `1dc8314` S5-02）
> **时间**：2026-11-08
> **证据**：`evidence/S4-QA/CANCEL-02/`
> **依据**：S4 §5.2（清理不得因再次取消跳过）；S5-02 回执
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 取消后清理路径开始 | **PASS**：`g_cleanup_started=1` |
| 清理路径完整执行 | **PASS**：`g_cleanup_done=1` |
| `close` 等清理完成后才返回 | **PASS**：`elapsed >= 40ms`（50ms 清理窗口） |
| 清理任务最终结果 | **PASS**：`ok=0, kind=Cancelled` |

**判定：PASS。** 取消请求不会跳过清理；组 close 阻塞到清理完成，随后交付 Cancelled。

---

## 二、实测

`test_cleanup_queued`（`impl/runtime/test_task.c`）：

```c
atomic_store(&g_cleanup_started, 0);
atomic_store(&g_cleanup_done, 0);
...
int64_t t0 = xrt_clock_mono_ms();
xrt_task_group_close(g, &fe);
int64_t elapsed = xrt_clock_mono_ms() - t0;
assert(g_cleanup_started == 1);
assert(g_cleanup_done == 1);   // 清理完整执行后 close 才返回
assert(elapsed >= 40);         // 未被取消提前打断
...
assert(r.kind == XRT_ERR_CANCELLED);
```

`build_rt.sh` exit 0，`task tests passed (... cleanup ...)`。

---

## 三、证据

- `evidence/S4-QA/CANCEL-02/matrix.tsv`
- `runtime-build.log`
- `source-contract.txt`（test_cleanup_queued 全文）
- `收件箱/回执箱/回执-S5-02.md`
