# 验收：S2/BND-02 类继承限制

> **验收人**：QA1（独立质量线）
> **结论：PASS**（A/R 全过，X01 语言级通过；工程清单模式为基础设施缺口）
> **被测**：current main `2ec03ac`（含 E4 `44d7ef1` BND-02 多级布局修复）
> **二进制**：`/tmp/xnull-s2-2ec03ac`，sha256 `be8793c6376a2a30e10971462b87c38309ee3344d7f75a21de9e8e6a28a04c9b`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §2.5/§2.6/§6.3；`收件箱/门/S2验收计划-QA.md` §2.4.3
> **时间**：2026-11-07

---

## 一、结论

| 项 | 结果 |
|---|---|
| A01 单父类字段/方法复用 | **PASS**：双路径 `1\n2\n3` |
| A02 多级继承 + 多协议 | **PASS**：双路径 `1\n2\n3\n4\n5\ntrue`（`d99c682` 的字段偏移回归已修） |
| R01 abstract 实例化 | **PASS**：`TY-210` @5:11 |
| R02 继承 final 类 | **PASS**：`TY-202` @3:7 |
| R03 子类同签名 / 字段隐藏 | **PASS**：`TY-203` @5:9 / @4:7 |
| X01 跨包 public/protected/private | **PASS**：双路径正例 + `TY-209` 负例 |
| X01 工程清单 build | **BLOCKED**：`CLI-003`，`xnull build` 工程模式未实现（非语言能力缺口） |
| 回归 | **PASS**：`TestInheritanceRules`、`TestS2InheritanceLayout` |

**判定：PASS（语言语义）。** 继承禁止面、跨包继承与可见性全部符合规范；多级继承 + 协议字段布局回归已消除。X01 的 `xnull.project` 工程构建属工具链未实现项，已由单文件跨包 run/check 等价验证，不作为本锚点失败。

---

## 二、逐项

| ID | 模式 | 期望 | 实测 | 判定 |
|---|---|---|---|---|
| S2-BND02-A01 | interp | `1\n2\n3` | `1\n2\n3`，rc=0 | PASS |
| S2-BND02-A01 | compiled | `1\n2\n3` | `1\n2\n3`，rc=0 | PASS |
| S2-BND02-A02 | interp | `1\n2\n3\n4\n5\ntrue` | `1\n2\n3\n4\n5\ntrue`，rc=0 | PASS |
| S2-BND02-A02 | compiled | 同上 | `1\n2\n3\n4\n5\ntrue`，rc=0 | PASS |
| S2-BND02-R01 | check | abstract `new` 拒绝 | rc=1；`r01_abstract_new.x:5:11 error[TY-210]` | PASS |
| S2-BND02-R02 | check | 继承 final 拒绝 | rc=1；`r02_final_parent.x:3:7 error[TY-202]` | PASS |
| S2-BND02-R03 | check | 子类同签名拒绝 | rc=1；`r03_override.x:5:9 error[TY-203]` | PASS |
| S2-BND02-R03b | check | 字段隐藏拒绝 | rc=1；`r03b_field_hide.x:4:7 error[TY-203]` | PASS |
| S2-BND02-X01 | cross-pkg | 跨包继承 + public `1\n2\n3` | 双路径 `1\n2\n3` | PASS |
| S2-BND02-X01 | cross-pkg | 子类访问 protected `7` | 双路径 `7` | PASS |
| S2-BND02-X01 | cross-pkg | private 拒绝 | rc=1；`TY-209` @3:26 | PASS |
| S2-BND02-X01 | project | `xnull build` rc=0 | rc=2；`CLI-003` | BLOCKED |

---

## 三、修复关闭项

| 前次失败（`d99c682`） | 修复 | 本轮 |
|---|---|---|
| A02 compiled `3\n2\n0\n4\n5\ntrue`（继承字段偏移） | `44d7ef1` | 双路径 `1\n2\n3\n4\n5\ntrue` |
| A01 compiled `incompatible pointer types` 告警 | `44d7ef1` | 告警消失，rc=0 |

---

## 四、证据

- 根目录：`evidence/S2-QA/BND-02-2ec03ac/`
- 汇总：`matrix.tsv`
- 用例：`S2-BND02-A01/`、`A02/`（interp+compiled）、`R01..R03b/`、`X01/{public-*,protected-*,private-check,project_build}/`
- 回归：`gotest-sema/`、`gotest-codegen/`
- 夹具：`difftest/s2/bnd02/`
- 每目录含 `cmd.txt/stdout.txt/stderr.txt/exit_code.txt/sha.txt`
