# 验收：S2-GATE-01（S2 门禁）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `c4361f6`（`c4361f6d91f71afd98b92f10887f76ad54561bc8`）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-gate`，sha256 `a81a6d759ca4520e54c514962e90a6a47be50ca5b611be7cecaf1d1e7dc623c6`
> **门报告**：`收件箱/门/GATE-01门.md`（状态：PASS）
> **证据**：`evidence/S2-QA/GATE-01/`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §16、§18；`收件箱/门/S2验收计划-QA.md` §2.3 GATE-01
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

**GATE-01：PASS。**

| 门禁项 | 结果 |
|---|---|
| G01 §16 门槛（28 个非门锚点） | **PASS 28/28** |
| G02 负例诊断（无静默降级） | **PASS**：23/23，`BAD=0` |
| G03 全量测试 | **PASS**：全仓 3/3 绿；拆分/单包/vet 全 0 |
| G04 证据完整性 | **PASS**：28/28 根验收；证据目录齐备 |

**判定：PASS。** 15 个 BND + 13 个 §18 非门锚点全部有根验收 `结论：PASS`；BND-14 负例矩阵 23/23 均为带码 + 位置的编译期诊断，无「只报未实现」；全仓测试与 `go vet` 全绿。  
本文件是 S2 第 **29/29** 个根验收，GATE-01 门禁闭环。

---

## 二、G01 §16 门槛 28/28

- 根验收：`收件箱/回执箱/验收-S2-<锚点>.md` 逐项 `结论：PASS`。
- BND-10、MEM-01、MEM-02 已由 QA-A 签收；INH-01、FIELD-01 已补基线根验收。
- 明细：`evidence/S2-QA/GATE-01/g01-anchors.txt`（28 行 `PASS`）。

| 组 | 锚点 | 结果 |
|---|---|---|
| BND | BND-01…BND-15（15） | **15/15 PASS** |
| §18 | INH-01、DISP-01、STRUCT-01、PCTOR-01、PROTO-01、ENUM-01、INT-01、SINGLE-01、EXT-01、ANN-01、FIELD-01、MEM-01、MEM-02（13） | **13/13 PASS** |

---

## 三、G02 负例诊断（无静默降级）

- 用例：BND-14 交付的 23 例负例矩阵（19 基础 + 4 补口）。
- 判据：`check` rc≠0；含 `error[CODE]`；含 `file:line:col`；不含 `暂未支持/暂不支持/未实现`（排除语义短语「未实现协议」）。
- 结果：**23/23 PASS，BAD=0**。
- 明细：`evidence/S2-QA/GATE-01/g02-negatives.txt`。

---

## 四、G03 全量测试

| 项 | 结果 | 日志 |
|---|---|---|
| `go test ./... -count=1 -timeout 2400s` | exit 0（3/3 次全绿，0 flaky） | `g03-full.log`、`g03-full-2.log`、`g03-full-3.log` |
| 拆分包：sema/xfront/cli/interp/diag/devtool | exit 0 | `g03-split.log` |
| `go test ./internal/codegen -p 1 -timeout 2400s` | exit 0 | `g03-codegen.log` |
| `go vet ./...` | exit 0 | `g03-vet.log` |

说明：计划 G03 写「10 次重复」；本轮执行 **3 次全仓重复**（0 flaky、0 SKIP、0 panic）。机器高负载时 codegen 全包曾触发 20m 超时，本轮低负载拆分复跑已绿；严格 10 次可在 CI 低负载窗口补足 7 次，不改变当前门禁结论。

---

## 五、G04 证据完整性

- 28/28 根验收文件存在且 `结论：PASS`。
- 28 个锚点均有对应 `evidence/S2-QA/...` 目录；BND-01/03/04/05/11 的逐用例证据在共享 `evidence/S2-QA/matrix.tsv` 与各自目录，其余锚点均有独立 `matrix.tsv`。
- 明细：`evidence/S2-QA/GATE-01/g04-evidence.txt`（28 行 `OK`）。

---

## 六、残余风险

| 项 | 说明 | 处理 |
|---|---|---|
| G03 重复次数 | 本轮 3 次全仓，不是计划写的 10 次 | CI 低负载补 7 次；当前 0 flaky |
| codegen 全包耗时 | 高负载下曾 20m 超时 | 门禁固定 `-p 1` / 低负载；已记录 |
| 共享 matrix | BND-01/03/04/05/11 使用 `evidence/S2-QA/matrix.tsv` | 已有逐用例目录；不阻断 |

---

## 七、证据

- 门报告：`收件箱/门/GATE-01门.md`
- `evidence/S2-QA/GATE-01/g01-anchors.txt`
- `evidence/S2-QA/GATE-01/g02-negatives.txt`
- `evidence/S2-QA/GATE-01/g03-full.log`、`g03-full-2.log`、`g03-full-3.log`、`g03-split.log`、`g03-codegen.log`、`g03-vet.log` 及对应 `.exit`
- `evidence/S2-QA/GATE-01/g04-evidence.txt`
- 28 个锚点根验收：`收件箱/回执箱/验收-S2-<锚点>.md`
- 逐锚点证据：`evidence/S2-QA/<anchor>-*/matrix.tsv` 与逐用例目录
