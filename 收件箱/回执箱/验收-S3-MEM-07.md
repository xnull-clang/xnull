# 验收：S3-MEM-07（Result）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（含 Result 字段的类 GC 判定通过；Result 值复制/字段初始化的编译路径未支持）
> **复验点**：main `412fcac`（S3 计划 v0.2 `31bf5f1`、S3-04 `7b50704`）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-s3b`，sha256 `d7fe3b72506598e04df2df831494680d6519b03be5e1a5c8a9c4480c3341dcba`
> **证据**：`evidence/S3-QA/MEM-07/`
> **依据**：`收件箱/门/S3验收计划-E2.md` MEM-07；S3 §9/§25；`XNull解决方案-第3部分-内存管理-v3.1.0-修订说明.md`
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 含 `Result` 字段的类按 GC 分析 | **PASS**：`xnull policy` 输出 `policy=gc`、`rule=5` |
| `Result` 内联值结构、无盒身份 | **部分**：C 侧为内联结构，但 `Result` 变量复制/字段初始化未支持 |
| `Result` 变量复制 `Result b = a` | **FAIL**：compiled rc=1，`Result 表达式 *xfront.IdentExpr 未支持（M4.1 范围）` |
| 类字段 `Result<Int,String> r = Ok(5)` | **FAIL**：compiled rc=1，`Int 表达式 *xfront.Call 未支持（M4.1 范围）` |
| 解释路径 Result 值复制/字段读取 | **PASS**：`true/true/7`，rc=0 |
| codegen `TestResult|TestS2` | **PASS**（未覆盖上述表达式形态） |

**判定：FAIL。** GC 判定面成立；Result 内联结构的“值”形态在编译路径不可用，值语义未闭合。

---

## 二、逐项实测

| 用例 | 期望 | check | interp | compiled | 判定 |
|---|---|---|---|---|---|
| `probe_result_copy` `Result b = a` + 传给类构造器 | 值复制可用 | rc=0 | `true/true/7`，rc=0 | **rc=1** `Result 表达式 *xfront.IdentExpr 未支持` | **FAIL** |
| `probe_class_field` `class C { Result<Int,String> r = Ok(5) }` | 字段初始化可用 | rc=0 | `true/5`，rc=0 | **rc=1** `Int 表达式 *xfront.Call 未支持` | **FAIL** |
| `policy_input` 含 Result 字段的类 | GC 判定 | rc=0 | — | `policy=gc, rule=5` | **PASS** |

---

## 三、失败项与归属

| # | 失败项 | 证据 | 归属 |
|---:|---|---|---|
| P-01 | Result 变量作为表达式未发射 | `probe1.run.err` | E4 codegen |
| P-02 | Result 字段初始化表达式未发射 | `probe2.run.err` | E4 codegen |
| P-03 | 现有 `TestResult|TestS2` 未覆盖 Result 值复制/字段初值 | `gotest.out` | QA 用例缺口 |

---

## 四、证据

- `evidence/S3-QA/MEM-07/matrix.tsv`
- `evidence/S3-QA/MEM-07/policy.out`、`policy_input.x`
- `evidence/S3-QA/MEM-07/probe_result_copy.x`、`probe1.*`
- `evidence/S3-QA/MEM-07/probe_class_field.x`、`probe2.*`
- `evidence/S3-QA/MEM-07/gotest.out`
