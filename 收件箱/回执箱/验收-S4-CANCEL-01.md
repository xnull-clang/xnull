# 验收：S4-CANCEL-01（取消错误面）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `87c2053`（含 E5 `1dc8314` S5-02 取消/超时）
> **时间**：2026-11-08
> **证据**：`evidence/S4-QA/CANCEL-01/`
> **依据**：S4 §5.1–§5.3、CANCEL-01；S5-02 回执
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 取消令牌（原子读） | **PASS**：`xrt_cancel_token_cancelled` 原子读 |
| 父取消 → 子 `check_cancel == Cancelled` | **PASS**：`test_cancel_token_and_deadline` |
| 取消任务以 `Err + Cancelled` 报告 | **PASS**：`test_cancel_close`：`r.ok=0, kind=XRT_ERR_CANCELLED` |
| 取消后清理路径不被跳过 | **PASS**（详见 CANCEL-02） |
| 不伪装/不降级（FFI `Cancelled` 映射） | **PASS**：`TestS4_04FFIErrorKindRuntime/Cancelled` |
| 解释器 `Context.cancel/checkCancel` | **PASS**：`TestS5TasksBasic/ContextCancel` |
| 副作用停止 | **PASS（协作式）**：任务体检查令牌后停止；组 close 等任务终止后才返回 Cancelled |

**判定：PASS。** 取消令牌、父链传播、`Cancelled` 错误值、清理排队与 FFI 映射均成立。取消是协作式的：运行时不抢占任务体，“副作用已停止”由任务体在检查令牌后返回 `Cancelled` 保证（S5-02 边界）。

---

## 二、实测

```text
$ sh impl/runtime/build_rt.sh
...
task tests passed (spawn/join/close/cancel/token/deadline/cleanup/timeout/root/panic)
exit 0
```

`test_cancel_token_and_deadline`：token 未取消 → 取消 root → token=1、child check_cancel=Cancelled；past deadline → Cancelled；future deadline → 0。

`test_cancel_close`：spawn 循环任务 → group close 取消并等待 → join 得 `ok=0, kind=Cancelled`。

`TestS4_04FFIErrorKindRuntime/Cancelled`：FFI 错误码 8 → `Cancelled`（非 Internal/Ok）。

`TestS5TasksBasic/ContextCancel`：`ctx.cancel()` 后 `checkCancel()` 返回 Err。

---

## 三、边界

| 项 | 说明 |
|---|---|
| 协作式取消 | 运行时不抢占；任务体必须周期性 `check_cancel`。S5-02 明确此边界 |
| 吞掉取消 | `unwrapOr` 等兜底仍可显式吞掉（§5.3 调用点可见），框架不做隐式拦截 |

---

## 四、证据

- `evidence/S4-QA/CANCEL-01/matrix.tsv`
- `runtime-build.log`（`task tests passed ... cancel/token/deadline/cleanup/timeout`）
- `source-contract.txt`（test_task.c 取消令牌/close 合同）
- `ffi-cancel-timeout.log`、`interp-tasks.log`
- `收件箱/回执箱/回执-S5-02.md`
