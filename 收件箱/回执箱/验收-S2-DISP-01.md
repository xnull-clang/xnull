# 验收：S2/DISP-01 派发模型

> **验收人**：QA1（独立质量线）
> **结论：PASS**（A01–A05 双路径全过）
> **被测**：current main `2ec03ac`（含 E3 `6d2d636`、E4 vtable `315fa9b`、`44d7ef1` is/as?/上转/可空协议）
> **二进制**：`/tmp/xnull-s2-2ec03ac`，sha256 `be8793c6376a2a30e10971462b87c38309ee3344d7f75a21de9e8e6a28a04c9b`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §5.2/§5.6/§5.7；`收件箱/门/S2验收计划-QA.md` §2.4.6
> **时间**：2026-11-07

---

## 一、结论

| 项 | 结果 |
|---|---|
| A01 类静态派发 | **PASS**：双路径 `1\n1`，无 C 类型告警 |
| A02 协议动态派发 | **PASS**：双路径 `2\n1` |
| A03 同结构 ARC/GC | **PASS**：双路径 `7\n7`（可空协议字段已支持） |
| A04 `super` 静态父实现 | **PASS**：双路径 `30` |
| A05 `is` / `as?` / 隐式上转 | **PASS**：`c is P`、`p is C`、`p as? C` 双路径 `true`；`P p = c` rc=0 |
| D01 双路径 | **PASS**：0 mismatch |

**判定：PASS。** §5.2 转换、§5.6 静态/动态派发、§5.7 vtable 在解释与编译路径一致；`d99c682` 的 A03/A05 回归已全部关闭。

---

## 二、逐项

| ID | 模式 | 期望 | 实测 | 判定 |
|---|---|---|---|---|
| S2-DISP-A01 | interp | `1\n1` | `1\n1`，rc=0 | PASS |
| S2-DISP-A01 | compiled | `1\n1` | `1\n1`，rc=0 | PASS |
| S2-DISP-A02 | interp | `2\n1` | `2\n1`，rc=0 | PASS |
| S2-DISP-A02 | compiled | `2\n1` | `2\n1`，rc=0 | PASS |
| S2-DISP-A03 | interp | `7\n7` | `7\n7`，rc=0 | PASS |
| S2-DISP-A03 | compiled | `7\n7` | `7\n7`，rc=0 | PASS |
| S2-DISP-A04 | interp | `30` | `30`，rc=0 | PASS |
| S2-DISP-A04 | compiled | `30` | `30`，rc=0 | PASS |
| S2-DISP-A05a | interp/compiled | `c is P` → `true` | `true`，rc=0 | PASS |
| S2-DISP-A05b | interp/compiled | `p is C` → `true` | `true`，rc=0 | PASS |
| S2-DISP-A05c | interp/compiled | `p as? C` 非 null → `true` | `true`，rc=0 | PASS |
| S2-DISP-A05d | check | `P p = c`（C implements P）rc=0 | rc=0，无诊断 | PASS |

---

## 三、修复关闭项

| 前次失败（`d99c682`） | 修复 | 本轮 |
|---|---|---|
| A03 compiled `可空类型 xn_proto_P 未支持` | `44d7ef1` | 双路径 `7\n7` |
| A05a/A05b compiled `is` 恒为 `0` | `44d7ef1` | 双路径 `true` |
| A05c compiled `as?` 可空类不支持 | `44d7ef1` | 双路径 `true` |
| A05d `P p = c` 被 `TY-101` 拒绝 | `44d7ef1` | rc=0 |
| A01 compiled `incompatible pointer types` | `44d7ef1` | 无告警 |

---

## 四、证据

- 根目录：`evidence/S2-QA/DISP-01-2ec03ac/`
- 汇总：`matrix.tsv`
- 用例：`S2-DISP-A01..A04/{interp,compiled}/`、`A05a..A05c/{interp,compiled}/`、`A05d/check/`
- 回归：`gotest-interp/`（6 例 PASS）、`gotest-codegen/`（`TestS2ProtocolVtableLayout` PASS）
- 夹具：`difftest/s2/disp01/`
- 每目录含 `cmd.txt/stdout.txt/stderr.txt/exit_code.txt/sha.txt`
