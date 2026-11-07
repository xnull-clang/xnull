# 验收：S3-MEM-07（Result）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（S3-RESULT `cb0dc0c` 补口后复签；Result 值复制/字段初始化双路径通过）
> **复验点**：main `bd95d86`（含 S3-RESULT `cb0dc0c`、S3-EXPR 补口）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-s3d`，sha256 `8db5c73c4877c5da12f650df4b0b9d8e28b335f34072d4046bc5ad9e3f193ac7`
> **证据**：`evidence/S3-QA/MEM-07-bd95d86/`
> **依据**：`收件箱/门/S3验收计划-E2.md` MEM-07；S3 §9/§25；`收件箱/回执箱/回执-S3-RESULT.md`
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `Result<Int,String> b = a` 值复制 | **PASS**：interp/compiled `5` |
| `class C { Result<Int,String> r = Ok(5) }` 字段初始化 | **PASS**：interp/compiled `5` |
| 字段 receiver `c.r.unwrapOr(0)` / `c.e.isErr()` | **PASS**（S3-RESULT 测试） |
| 字段赋值 `c.r = Ok(7)` / 构造器内 `self.copy = self.r` | **PASS**（S3-RESULT 测试） |
| 含 `Result` 字段的类按 GC 分析 | **PASS**：`policy=gc, rule=5` |
| `TestS3_RESULT` / `TestResult` / `TestS2` | **PASS** |

**判定：PASS。** 上一轮 `Result 表达式 *xfront.IdentExpr 未支持` / `Int 表达式 *xfront.Call 未支持` 已由 `cb0dc0c` 关闭；repro-copy/repro-field 双路径一致。

---

## 二、逐项实测

| 用例 | check | interp | compiled | 判定 |
|---|---|---|---|---|
| `repro-copy.x` `Result b = a` + 函数传参 | rc=0 | `5`，rc=0 | `5`，rc=0 | **PASS** |
| `repro-field.x` `Result` 字段初始化/成员 | rc=0 | `5`，rc=0 | `5`，rc=0 | **PASS** |
| 含 Result 字段的类 `xnull policy` | rc=0 | — | `policy=gc, rule=5` | **PASS** |
| `TestS3_RESULTCopy` / `FieldInitAndReceiver` / `FieldCopyInCtor` | — | — | PASS | **PASS** |

---

## 三、边界

| 项 | 现状 | 建议 |
|---|---|---|
| `Result` 作类构造器**参数**类型 | compiled 仍报 C 编译错误 `unknown type xn_Result_Int_String`（typedef 顺序） | E4 后续卡；不属本次 S3-RESULT repro 范围 |

---

## 四、证据

- `evidence/S3-QA/MEM-07-bd95d86/matrix.tsv`
- `repro-copy.x` / `repro-field.x` 的 `check/interp/compiled` 输出与 exit
- `policy.out`、`gotest.out`
- 复用 `evidence/S3-RESULT/`（红→绿原始证据）
