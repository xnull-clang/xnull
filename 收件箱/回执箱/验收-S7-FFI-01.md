# 验收：S7-FFI-01（错误码合同）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（错误码映射/去 fatal 通过；同步 FFI 仍未返回 Result，仍为原始码 + 出参）
> **复验点**：main `eeb7b04`（含 E5 S7-02 `bd210bb` 测试）
> **时间**：2026-11-08
> **证据**：`evidence/S7-QA/FFI-01/`
> **依据**：S7 §7.3、FFI-01；S7-02 验收计划；`回执-S7-02-E5.md`
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 已知码 5 → `NotFound` | **PASS** |
| 未知码 99 → `Internal`（不为 Ok） | **PASS** |
| `Cancelled` / `Timeout` 不降级 | **PASS**：14/15 映射保持 |
| 错误码即返回值/出参不再 `exit(134)` | **PASS**：`5\n0\n` / `7`，调用点继续 |
| 未知码不静默成功 | **PASS** |
| 无租约/非法跨边界类型拒绝 | **PASS**：`TestContractNegatives` |
| **同步 FFI 返回 `Result<T,Error>`** | **FAIL**：签名仍为 `Int64`/`Int32` 原始码 + `Int32 code` 出参 |

**判定：FAIL。** E5 只完成运行时映射与“去 fatal”；语言层 `Result<T,Error>` 返回仍属 E4/E2，未落地。

---

## 二、实测

```text
$ go test ./internal/codegen/ffi -run TestS7_02 -count=1 -v
PASS TestS7_02ErrorKindMappingRuntime
  -> 5→NotFound, 99→Internal, 14→Cancelled, 15→Timeout

$ go test ./internal/codegen -run TestS7_02 -count=1 -v
PASS TestS7_02ErrorCodeNoFatal        # stdout 5\n0
PASS TestS7_02ErrorKindExpr
PASS TestS7_02ErrorCodeReturnNoFatal  # stdout 7
```

但用例签名仍是：

```x
Int64 ffiRead(String path, Int32 code)   // 原始码 + 出参
Int32 ffiWrite(Int32 v)                  // 错误码即返回值
```

无 `Result<T, Error>` 形态；`回执-S7-02-E5.md` 明确：“语言签名改成 `Result<T,Error>` 仍属 E4/E2”。

---

## 三、失败项与归属

| # | 失败项 | 证据 | 归属 |
|---:|---|---|---|
| P-01 | 同步 FFI 未返回 `Result<T,Error>` | `impl/internal/codegen/s7_02_test.go` | E4 codegen + E2 sema |
| P-02 | 调用点仍靠出参变量取错误码 | `s702Xfb` / `s702RetXfb` | E4 |
| P-03 | `ffiErrorKindExpr` 只有生成侧 helper，未接入 Result 构造 | `TestS7_02ErrorKindExpr` | E4 |

已通过面：映射表、未知码 Internal、取消/超时不降级、去 `exit(134)`、合同负例。

---

## 四、放行条件

1. E2/E4：同步 FFI 声明改为 `Result<T, Error>`（或等价错误值），调用点直接 `Ok/Err`。
2. 已知码 → `Err(kind)`，未知 → `Err(Internal)`，Cancelled/Timeout 保持。
3. 复跑 A01–A06/R01–R03/M01/D01；端到端无 fatal。

---

## 五、证据

- `evidence/S7-QA/FFI-01/matrix.tsv`
- `ffi-s702.log`（映射运行时）
- `codegen-s702.log`（去 fatal / 原始码交付）
- `impl/internal/codegen/s7_02_test.go`
- `收件箱/回执箱/回执-S7-02-E5.md`
