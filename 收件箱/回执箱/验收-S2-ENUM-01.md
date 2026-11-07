# 验收：S2/ENUM-01 枚举

> **验收人**：QA1（独立质量线）
> **结论：PASS**（A/R/D 全过；`default` 位置已修）
> **被测**：current main `d107f33`（含 E2 `aca8e25` default 必须最后）
> **二进制**：`/tmp/xnull-s2-d107f3340e9dbcd78e545339703d24b75b8d4fd8`，sha256 `3b3d9864d946ee0ac80968d4bc358a0bbc5b8ebc4684251d5828efadffe69d60`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §8.1–§8.6；`收件箱/门/S2验收计划-QA.md` §2.4.5
> **时间**：2026-11-07

---

## 一、结论

| 项 | 结果 |
|---|---|
| A01 简单枚举格式化 | **PASS**：双路径 `Green` |
| A02 穷尽 switch | **PASS**：双路径 `g` |
| A03 数据枚举项/字段 | **PASS**：双路径 `Ready\n0` |
| A04 `default` 在最后（合法） | **PASS**：双路径 `r` |
| R01 非穷尽 | **PASS**：`TY-213` @4:5 |
| R02 重复/未知 case | **PASS**：`TY-213` @7:19 / @12:19 |
| R03 `default` 非最后 | **PASS**：`TY-213` @5:9（`d107f33` 新修） |
| R03 多个 `default` | **PASS**：`SYN-101` @4:5 |
| R04 enum implements protocol | **PASS**：`SYN-101` @2:12 |
| D01 双路径 | **PASS**：A01–A04 一致 |

**判定：PASS。** §8.5 `default` 必须最后的约束已生效；`default` 最后仍合法，未误伤。

---

## 二、逐项

| ID | 模式 | 期望 | 实测 | 判定 |
|---|---|---|---|---|
| S2-ENUM-A01 | interp/compiled | `Green` | `Green`，rc=0 | PASS |
| S2-ENUM-A02 | interp/compiled | `g` | `g`，rc=0 | PASS |
| S2-ENUM-A03 | interp/compiled | `Ready\n0` | `Ready\n0`，rc=0 | PASS |
| S2-ENUM-A04 | interp/compiled | `r` | `r`，rc=0 | PASS |
| S2-ENUM-R01 | check | 非穷尽拒绝 | rc=1；`r01_non_exhaustive.x:4:5 error[TY-213]` 遗漏 Green、Blue | PASS |
| S2-ENUM-R02-dup | check | 重复 case 拒绝 | rc=1；`r02_dup_case.x:7:19 error[TY-213]` | PASS |
| S2-ENUM-R02-unknown | check | 未知项拒绝 | rc=1；`r02_unknown.x:12:19 error[TY-213]` | PASS |
| S2-ENUM-R03-first | check | `default` 非最后拒绝 | rc=1；`r03_default_first.x:5:9 error[TY-213] default 子句必须位于 switch 最后` | PASS |
| S2-ENUM-R03-two | check | 多个 `default` 拒绝 | rc=1；`4:5 error[SYN-101] default 子句最多一个` | PASS |
| S2-ENUM-R04 | check | enum implements 拒绝 | rc=1；`2:12 error[SYN-101]` | PASS |

---

## 三、修复关闭项

| 前次失败（`8f50690`） | 修复 | 本轮 |
|---|---|---|
| `default` 位于 case 之前仍 rc=0 | `aca8e25` | `TY-213` @5:9 |
| `default` 最后（合法） | — | 双路径 `r`，未误伤 |

---

## 四、证据

- 根目录：`evidence/S2-QA/ENUM-01-d107f33/`
- 汇总：`matrix.tsv`
- 用例：`S2-ENUM-A01..A04/{interp,compiled}/`、`R01/`、`R02-dup/`、`R02-unknown/`、`R03-first/`、`R03-two/`、`R04/`（各 `check/`）
- 回归：`gotest-sema/`（`TestEnumRules`、`TestS2BND06EnumSwitch` PASS）、`gotest-interp/`（3 例 PASS）、`gotest-codegen/`（2 例 PASS）
- 夹具：`difftest/s2/enum01/`
- 每目录含 `cmd.txt/stdout.txt/stderr.txt/exit_code.txt/sha.txt`
