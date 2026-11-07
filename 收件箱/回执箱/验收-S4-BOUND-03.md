# 验收：S4-BOUND-03（FFI 取消/超时映射）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `72c5d3f`（含 S4-04 FFI errorMap `c8f98f8`、S5-02 取消/超时映射骨架；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-BOUND03/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| FFI `errorMap` 已知码 → `ErrorKind` | **PASS**：5→NotFound、14→Cancelled、15→Timeout |
| `Cancelled` 不降级为 `Internal` | **PASS**：`case 14: return XRT_ERR_CANCELLED;` |
| `Timeout` 不降级为 `Internal` | **PASS**：`case 15: return XRT_ERR_TIMEOUT;` |
| 未知码不映射为 `Ok` | **PASS**：`default: return XRT_ERR_INTERNAL;`；`xrt_error_kind_parse("nope"/NULL) → INTERNAL` |
| 全部 `ErrorKind` 规范名映射 | **PASS**：14 项 + 历史别名（Invalid/Conflict/Permission/Limit） |
| 运行时错误面骨架 | **PASS**：`xrt_error_kind_name/parse`、`XRT_ERR_TIMEOUT=6`、`XRT_ERR_CANCELLED=7` |
| 任务取消/超时骨架 | **PASS**：`rt_task.c` 返回 `XRT_ERR_CANCELLED`/`XRT_ERR_TIMEOUT`；task tests 全过 |

**判定：PASS。** `c8f98f8` 的 FFI `errorMap` 覆盖了 Cancelled/Timeout，未知码默认 `Internal`（不是 `Ok`）；S5-02 的取消/超时错误面骨架已接线。台账 BOUND-03 可登记为 PASS。

---

## 二、FFI 映射

`TestErrorKindEnumHelper`（`emit_test.go`）构造：

```text
errorMap {
  5 = NotFound
  14 = Cancelled
  15 = Timeout
}
```

断言生成 C 包含：

```c
case 14: return XRT_ERR_CANCELLED;
case 15: return XRT_ERR_TIMEOUT;
case 5: return XRT_ERR_NOT_FOUND;
default: return XRT_ERR_INTERNAL;
```

全部 PASS。`errorKindEnum` 覆盖 S4 §3.1 的 14 个规范名，另兼容历史短名 `Invalid/Conflict/Permission/Limit`；未知名落到 `XRT_ERR_INTERNAL`。

---

## 三、未知码不降级为 Ok

`TestXdkWrappersRun` 断言：

```text
read rc=5 kind=NotFound
unknown=Internal
```

`TestContractNegatives` 11 子项全过（含 `Result_跨界` FFI-105）。  
运行时 `test_std.c` 的错误面骨架：

```c
xrt_error_kind_parse("Timeout")   == XRT_ERR_TIMEOUT   // 6
xrt_error_kind_parse("Cancelled") == XRT_ERR_CANCELLED // 7
xrt_error_kind_parse("nope")      == XRT_ERR_INTERNAL
xrt_error_kind_parse(NULL)        == XRT_ERR_INTERNAL
```

`runtime-build.log`：`task tests passed (spawn/join/close/cancel/timeout/root/panic)`。

---

## 四、边界

S5-02 为取消/超时**错误面骨架**：调度器挂起点、副作用停止、清理不跳过等运行时契约仍随 B3；BOUND-03 只验 FFI `errorMap` 分类不降级与未知码不映射 `Ok`，不把 B3 调度语义计入本轮。

---

## 五、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-BOUND03/ffi-bound03.log`（`TestErrorKindEnumHelper`、`TestXdkWrappersRun`）
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-BOUND03/contract.txt`（映射代码/运行时枚举）
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-BOUND03/runtime-build.log`（task/error-kind 骨架）
- 断言依据：S4 §7.3、§10 BOUND-03；S7 §7.2 / INV-FFI-2；S5-02 错误面
