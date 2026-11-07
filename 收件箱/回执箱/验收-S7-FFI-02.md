# 验收：S7-FFI-02（布局与标量映射）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `eeb7b04`（含 S7-01 `21a60a0` 调用点编组）
> **时间**：2026-11-08
> **证据**：`evidence/S7-QA/FFI-02/`
> **依据**：S7 §3.2–§3.5、FFI-02；S7-01 E2/E4 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `Text` 参数/返回（bytes+len） | **PASS**：`ffiText("abc")` → 3 |
| `layout(c)` 字段布局与 C 一致 | **PASS**：Pair {Int64,Int32} → 9；`_Static_assert(sizeof==16)` |
| 标量数组 `Int[]` data/len | **PASS**：`[1,2,3]` → 6 |
| `Float` / `Char` / `UInt` / 定宽整型 | **PASS**：3 / 'b' / 5 |
| layout 尺寸合法/非法检查 | **PASS**：`TestS701LayoutSize` |
| 未投射类型仅句柄/封送 | **PASS**：`TestS701FFICallTypes` |
| 调用点编组端到端 | **PASS**：`TestS701CallSiteMarshalling` |

**判定：PASS。** layout 逐字段布局、C 尺寸断言与标量映射全表通过；输出 `3/9/6/3/true/5/2/2/0/true` 与期望一致。

---

## 二、实测

```text
$ go test ./internal/codegen -run TestS701 -count=1 -v
PASS TestS701CallSiteMarshalling

$ go test ./internal/sema -run TestS701 -count=1 -v
PASS TestS701LayoutSize / TestS701FFICallTypes
```

生成 C 含 `_Static_assert(sizeof(xn_layout_Pair) == 16, ...)`；layout 非法模式子进程终止。

---

## 三、边界

| 项 | 说明 |
|---|---|
| 数组元素 | 限标量/layout；引用元素数组仍拒绝（S7 §3.5） |
| Text 返回 | 原生须返回 NUL 结尾 C 串（与 String 同约定） |
| 嵌套 layout | 按依赖顺序登记（已覆盖合法/非法尺寸） |

---

## 四、证据

- `evidence/S7-QA/FFI-02/matrix.tsv`
- `codegen-s701.log`、`sema-s701.log`
- `impl/internal/codegen/s701_test.go`
- `收件箱/回执箱/回执-S7-01-E4.md`、`回执-S7-01-E2.md`
