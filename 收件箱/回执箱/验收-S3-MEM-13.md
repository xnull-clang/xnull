# 验收：S3-MEM-13（优化语义回归）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（大部分§20落地项回归通过；Result 内联值语义未闭合）
> **复验点**：main `412fcac`（S3 计划 v0.2 `31bf5f1`、S3-04 `7b50704`）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-s3b`，sha256 `d7fe3b72506598e04df2df831494680d6519b03be5e1a5c8a9c4480c3341dcba`
> **证据**：`evidence/S3-QA/MEM-13/`、`evidence/S3-QA/MEM-07/`
> **依据**：`收件箱/门/S3验收计划-E2.md` MEM-13；S3 §20/§25
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| §20 优化 | 验收点 | 结果 |
|---|---|---|
| 纯值免管理 | struct/简单枚举值语义 | **PASS**：S2 既有回归 |
| 无引用载荷免扫描 | String/Text/Bytes/SB 字段/字节区 | **PASS**：`TestS3_04*` |
| Result 内联 | 判别 + 载荷内联、值语义 | **FAIL**：`Result b = a`、`Result` 字段初始化 compiled rc=1（见 MEM-07） |
| 分配消除（栈） | 非逃逸类/闭包栈分配、身份不变 | **PASS**：`TestS3_03*` |
| 紧凑布局 | 8 字节槽 ABI | **PASS**：`TestS3_09ClassFieldSlots` |
| ARC 非原子化 | 未声明落地 | 不适用（未声明） |

**判定：FAIL。** Result 内联已落地但值表达式（变量复制/字段初值）在编译路径不可用，违反“优化不得改变值语义”的回归要求；其余已落地优化的回归用例通过。

---

## 二、实测

```text
$ go test ./internal/codegen -run 'TestS3_01|TestS3_03|TestS3_04|TestS3_05|TestS3_09|TestS2INT01' -count=1
ok  xnull.dev/xnull/internal/codegen

$ go test ./internal/codegen -run 'TestResult|TestS2' -count=1
ok  xnull.dev/xnull/internal/codegen
```

但补充探针：

```text
$ xnull run probe_result_copy.x
xnull: 代码生成失败：codegen：Result 表达式 *xfront.IdentExpr 未支持（M4.1 范围）

$ xnull run probe_class_field.x
xnull: 代码生成失败：codegen：Int 表达式 *xfront.Call 未支持（M4.1 范围）
```

→ Result 内联的“值”语义未通过，MEM-13 不能判 PASS。

---

## 三、失败项与归属

| # | 失败项 | 证据 | 归属 |
|---:|---|---|---|
| P-01 | Result 内联值复制/字段初值未发射 | `../MEM-07/probe1.run.err`、`probe2.run.err` | E4 codegen |
| P-02 | §20 “Result 内联”回归用例未覆盖值表达式 | `gotest.out` | QA/E4 用例缺口 |

---

## 四、证据

- `evidence/S3-QA/MEM-13/gotest.out`（优化回归）
- `evidence/S3-QA/MEM-13/policy.out`
- `evidence/S3-QA/MEM-13/matrix.tsv`
- 复用 `evidence/S3-QA/MEM-07/probe1.*`、`probe2.*`
