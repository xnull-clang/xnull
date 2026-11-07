# 验收：S3-MEM-13（优化语义回归）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（S3-RESULT `cb0dc0c` 补口后复签；§20 已落地优化回归通过）
> **复验点**：main `bd95d86`（含 S3-RESULT `cb0dc0c`、S3-EXPR 补口）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-s3d`，sha256 `8db5c73c4877c5da12f650df4b0b9d8e28b335f34072d4046bc5ad9e3f193ac7`
> **证据**：`evidence/S3-QA/MEM-13-bd95d86/`、`evidence/S3-QA/MEM-07-bd95d86/`
> **依据**：`收件箱/门/S3验收计划-E2.md` MEM-13；S3 §20/§25；`收件箱/回执箱/回执-S3-RESULT.md`
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| §20 优化 | 验收点 | 结果 |
|---|---|---|
| 纯值免管理 | struct/简单枚举值语义 | **PASS**：S2 既有回归 |
| 无引用载荷免扫描 | String/Text/Bytes/SB 字段/字节区 | **PASS**：`TestS3_04*` |
| Result 内联 | 判别 + 载荷内联、值复制/字段初始化 | **PASS**：repro-copy/repro-field 双路径 `5`；`TestS3_RESULT` 3/3 |
| 分配消除（栈） | 非逃逸类栈分配、身份不变 | **PASS**：`TestS3_03*` |
| 紧凑布局 | 8 字节槽 ABI | **PASS**：`TestS3_09ClassFieldSlots` |
| ARC 非原子化 | 未声明落地 | 不适用（未声明） |

**判定：PASS。** S3-RESULT 补口后 Result 内联值语义通过；`tests/s3/run.sh --compiled` 11/11 PASS，0 FAIL。

---

## 二、实测

```text
$ go test ./internal/codegen -run 'TestS3_01|TestS3_03|TestS3_04|TestS3_05|TestS3_09|TestS2INT01|TestS3_RESULT' -count=1
ok  xnull.dev/xnull/internal/codegen

$ bash tests/s3/run.sh --compiled --bin /tmp/xnull-s3d
汇总：PASS=11 FAIL=0
exit 0
```

Result 内联补口：`repro-copy.x` / `repro-field.x` 双路径均 `5`，rc=0。

---

## 三、边界

| 项 | 现状 |
|---|---|
| Result 作构造器参数 | 仍有一个 typedef 顺序缺口（见 MEM-07 边界）；不属本次 S3-RESULT repro 范围 |

---

## 四、证据

- `evidence/S3-QA/MEM-13-bd95d86/gotest.out`
- `evidence/S3-QA/MEM-13-bd95d86/tests-s3-compiled.log`（PASS=11 FAIL=0）
- `evidence/S3-QA/MEM-13-bd95d86/policy.out`
- `evidence/S3-QA/MEM-07-bd95d86/repro-*.{interp,compiled}.out`
- `evidence/S3-RESULT/`（红→绿原始证据）
