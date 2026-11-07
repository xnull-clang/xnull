# 验收：S7-FFI-01（FFI 错误码合同）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（FFI-01 修复后复签；同步 FFI 已返回 `Result<T, ErrorKind>`）
> **复验点**：main `feddcd1`（含 E4 `2f1bdf2` 同步 FFI Result 修复）
> **时间**：2026-11-08
> **证据**：`evidence/S7-QA/FFI-01b/`
> **依据**：S7 §7.1/§7.3、FFI-01；S7-02 验收计划；S7-02 E5 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 同步 FFI 返回 `Result<T, ErrorKind>` | **PASS**：`Result<Int64, ErrorKind>` / `Result<void, ErrorKind>` |
| 已知码 5 → `NotFound` | **PASS**：`Err(NotFound)` |
| 未知码 99 → `Internal`（非 Ok） | **PASS** |
| `Cancelled` / `Timeout` 不降级 | **PASS**：14/15 保持 |
| rc=0 → `Ok(value)` | **PASS** |
| 无 `exit(134)` | **PASS**：生成 C 无 FFI fatal；调用点返回 Result |
| 运行时映射 helper | **PASS**：`TestS7_02ErrorKindMappingRuntime` |

**判定：PASS。** 上一轮“仍为原始码 + 出参”的缺口已由 `2f1bdf2` 关闭；同步 FFI 在调用点直接构造 `Result<T, ErrorKind>`。

---

## 二、实测

```text
$ go test ./internal/codegen -run 'TestS7_02' -count=1 -v
PASS TestS7_02ErrorCodeNoFatal
PASS TestS7_02ErrorKindExpr
PASS TestS7_02ErrorCodeReturnNoFatal
PASS TestS7_02ResultMapping
  PASS Ok / 已知码 5 / 未知码 99 / Cancelled / Timeout

$ go test ./internal/codegen/ffi -run TestS7_02 -count=1 -v
PASS TestS7_02ErrorKindMappingRuntime
```

调用点签名：

```x
Result<Int64, ErrorKind> r = ffiRead("x")     // errorCode 出参
Result<void, ErrorKind> r = ffiWrite(1)       // 错误码即返回值
```

生成 C 含 `xn_Result_Int64_ErrorKind` 与 `xn_ffi_native_error_kind_id(`，无 FFI `exit(134)`。

---

## 三、边界

| 项 | 说明 |
|---|---|
| close 入口 | 句柄 close 仍以 `Bool` 暴露（幂等关闭，兼容既有面） |
| `@errorCode` 出参失败 | 结果槽不保证有效，先看 Result 的 `Err` |
| 未知码 | 不静默成 Ok；`Internal` |

---

## 四、证据

- `evidence/S7-QA/FFI-01b/matrix.tsv`
- `codegen-s702.log`（NoFatal / ReturnNoFatal / ResultMapping）
- `ffi-s702.log`（运行时映射）
- `source-contract.txt`（Result 映射用例）
- `收件箱/回执箱/回执-S7-02-E5.md`
