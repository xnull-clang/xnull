# 验收：S6-XDK-03（errors）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（按 ADR-008 `report -> void` 复验；compiled Error 协议为边界）
> **复验点**：main `d4f0209`（ADR-008 生效；`errors.x` report void）
> **时间**：2026-11-08
> **证据**：`evidence/S6-QA/XDK-03/`
> **依据**：ADR-008；S4 §2.1；S6 §4.1（编辑性修订为 void）；XDK-03 验收计划
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `ErrorKind` 14 项顺序 | **PASS**：`TestXdkErrorsUnitSurface` |
| `Error` 协议恰 2 成员（kind/describe） | **PASS** |
| `CauseError` 含 `cause: Error?` | **PASS** |
| `report -> void`（ADR-008） | **PASS**：`Result x = report(r)` → `TY-101`；语句形态可执行 |
| `report` 格式 `[Kind] describe` | **PASS**：`errors.x` 使用 `diagnose($"[{kind}] {describe}")` |
| `wrap` 丢弃换新 / `mapErr` 转换 | **PASS**：`TestS4WrapMapErr`、`TestS4Report` |
| 源码单元解析/语义/单测 | **PASS** |
| compiled `report(Error 协议)` | **BOUNDARY**：codegen `report 不支持错误类型 xrt_error_kind`（E4） |

**判定：PASS。** ADR-008 已消除 `report` 返回类型冲突；按 void 口径，源码单元、sema、interp 与格式合同全部成立。compiled Error 协议错误类型归 E4 语言面，不阻塞本锚点的 source/sema/interp 层判定。

---

## 二、实测

```text
$ go test ./internal/codegen -run TestXdkErrorsUnitSurface -count=1
PASS

$ go test ./internal/interp -run 'TestS4BuiltinXDKErrors|TestErrdeferOnlyOnErrorPath|TestS4WrapMapErr|TestS4Report' -count=1
PASS

$ xnull check report_assign.x
error[TY-101]: 变量 x 的初始化式类型 void 不能赋给 Result<Int,E>
```

`errors.x`：`void report<T>(Result<T, Error> r)`；失败 `diagnose($"[{r.error().kind()}] {r.error().describe()}")`，成功零输出。

---

## 三、边界

| 项 | 现状 | 归属 |
|---|---|---|
| compiled `report(Result<T, Error 协议>)` | `report 不支持错误类型 xrt_error_kind（S4-02）` | E4 语言面 |
| S6 §4.1 “返回原 Result” | ADR-008 编辑性修订为 void | 已裁决 |

---

## 四、证据

- `evidence/S6-QA/XDK-03/matrix.tsv`
- `gotest-codegen.out`、`gotest-interp.out`
- `report_void.x` / `report_assign.x` 及 check/interp/compiled 输出
- `impl/lib/xdk/errors.x`
- `ADR/ADR-008-report返回void裁决.md`
