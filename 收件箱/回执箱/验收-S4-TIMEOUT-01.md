# 验收：S4-TIMEOUT-01（超时）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `87c2053`（含 E5 `1dc8314` S5-02）
> **时间**：2026-11-08
> **证据**：`evidence/S4-QA/TIMEOUT-01/`
> **依据**：S4 §6.1–§6.2、TIMEOUT-01；S5-02 回执
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `joinDeadline` 超时返回 `Timeout` | **PASS**：`rc == XRT_ERR_TIMEOUT` |
| 超时非 panic/fatal | **PASS**：普通错误返回，进程继续 |
| 超时后任务继续、资源终态确定 | **PASS**：随后 `join` 得 `ok=1, value=7` |
| `with_deadline` 到期等效 `Cancelled` | **PASS**：past deadline → `XRT_ERR_CANCELLED` |
| FFI `Timeout` 映射不降级 | **PASS**：`TestS4_04FFIErrorKindRuntime/Timeout` |

**判定：PASS。** 超时以 `Timeout` 错误返回，不消费任务结果；任务可继续完成，资源终态确定。精度为“不早于到期后尽快生效”（§6.2）。

---

## 二、实测

`test_join_deadline`（`test_task.c`）：

```c
assert(xrt_task_group_spawn(g, body_slow, NULL, &t) == 0);
int rc = xrt_task_join_deadline(t, xrt_clock_mono_ms() + 5, &r);
assert(rc == XRT_ERR_TIMEOUT);          // 超时 = Timeout，非 panic
assert(xrt_task_join(t, &r) == 0);
assert(r.ok == 1 && (intptr_t)r.value == 7);  // 不消费结果，任务继续
```

`test_cancel_token_and_deadline`：past deadline → `XRT_ERR_CANCELLED`。

`TestS4_04FFIErrorKindRuntime/Timeout`：FFI 错误码 7 → `Timeout`。

---

## 三、证据

- `evidence/S4-QA/TIMEOUT-01/matrix.tsv`
- `runtime-build.log`
- `source-contract.txt`（test_join_deadline）
- `ffi-timeout.log`
- `收件箱/回执箱/回执-S5-02.md`
