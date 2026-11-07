# 验收：S2-BND-15（集成：Result/try/defer × 对象/factory/枚举）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（本轮集成矩阵 A01–A04 双路径全过；`new T[count]` / 标签控制为边界）
> **复验点**：main `e150227`（`e150227222bc4cbe9d3bd004e65ea61ce3814774`；含 E4 `c5bcc4e` BND-15 集成 codegen）
> **时间**：2026-11-07
> **二进制**：`/tmp/xnull-s2-bnd15`，sha256 `d2b24536cbfc0553c8e4df23166d107e42e740661240040d2cd5c9472e660366`
> **证据**：`evidence/S2-QA/BND-15-e150227/`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §16 BND-15；`收件箱/门/S2验收计划-QA.md` §2.3 BND-15
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| Result/try/defer × class | **PASS**：双路径 `m-err/m-defer/dR/outer-defer/outer-err/caught:bad` |
| 对象 + factory + Result（`try F.open`） | **PASS**：双路径 `f-defer/ok/false/f-err/f-defer/boom` |
| Result/try × 枚举穷尽 switch × struct | **PASS**：双路径 `g/9/false` |
| try 赋值（非声明）到对象 | **PASS**：双路径 `ok/false` |
| 双路径一致（D01） | **PASS**：A01–A04 stdout/rc 全一致 |
| 官方 codegen 用例 | **PASS**：`TestS2BND15TryFactoryObject/TryEnumStruct/TryAssignObject`、`TestS2INT01*` |

**判定：PASS（本轮集成矩阵）。** E4 `c5bcc4e` 已闭合对象/工厂/枚举/struct 的 `try` 解包、defer/errdefer 顺序与跨 Result 值类型传播。

---

## 二、逐项实测

| 用例 | 期望 | interp | compiled | 判定 |
|---|---|---|---|---|
| `a01_result_class` Result/try/defer + class + deinit | `m-err\nm-defer\ndR\nouter-defer\nouter-err\ncaught:bad` | 一致，rc=0 | 一致，rc=0 | **PASS** |
| `a02_factory_try` factory 返回 `Result<Device,String>` + try | `f-defer\nok\nfalse\nf-err\nf-defer\nboom` | 一致，rc=0 | 一致，rc=0 | **PASS** |
| `a03_enum_struct_try` `try` 解包枚举/struct + 穷尽 switch | `g\n9\nfalse` | 一致，rc=0 | 一致，rc=0 | **PASS** |
| `a04_try_assign` `d = try F.open(true)` | `ok\nfalse` | 一致，rc=0 | 一致，rc=0 | **PASS** |

---

## 三、边界（不改变本轮集成判定）

| 项 | 现状 | 证据 |
|---|---|---|
| `new T[count]` + class/struct | interp/compiled 均失败；codegen `容器表达式 *xfront.NewArray 未支持（M4.4a 范围）` | `S2-BND15-a05_new_array/` |
| 标签控制 + 枚举 switch | interp `2` rc=0；compiled `语句 *xfront.LabeledStmt 未支持（M4.1 范围）` | `S2-BND15-a06_labels/` |

这两项属于 BND-15 §16 行的 S1 控制流/数组部分，不在 E4 `c5bcc4e`（Result/try 集成）范围；若按 BND-15 全行验收，需另卡关闭。本轮按任务指定的 Result/try/defer × 对象/factory/枚举范围判 PASS。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/codegen -run 'TestS2BND15\|TestS2INT01' -count=1` | PASS |
| `go test ./internal/sema ./internal/codegen ./internal/xfront ./internal/cli ./internal/interp -count=1` | 全绿 |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1` | exit 0（当前主工作树） |

---

## 五、证据

- `evidence/S2-QA/BND-15-e150227/matrix.tsv`
- `evidence/S2-QA/BND-15-e150227/S2-BND15-a01_result_class/{check,interp,compiled}/` … `a04_try_assign/`
- `evidence/S2-QA/BND-15-e150227/S2-BND15-a05_new_array/`、`a06_labels/`（边界）
- `evidence/S2-QA/BND-15-e150227/gotest-codegen/`、`regression-*/`
- 夹具：`wt/qa-1/difftest/s2/bnd15/`
