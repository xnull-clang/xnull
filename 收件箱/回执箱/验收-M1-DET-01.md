# 验收：M1-DET-01（确定性，S1 §9 / §13）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（3/3）
> **复验点**：main `d620ea5`
> **时间**：2026-11-07

---

## 一、结论

| # | 台账验收要点 | 结果 | 证据 |
|---:|---|---|---|
| a | 相同源程序 → 相同诊断 | **PASS** | 5 个 DET 用例全绿（sema 2） |
| b | 相同源程序 → 相同运行结果 | **PASS** | 解释 10 次、编译 10 次同一 sha256；跨路径一致 |
| c | 初始化顺序不依赖文件系统枚举顺序 | **PASS** | `TestDET01InitOrderIndependentOfCreationOrder` |

`go test ./internal/sema ./internal/interp ./internal/codegen -run TestDET01` → 5 PASS，rc=0。

---

## 二、逐项实测

### a. 诊断稳定

| 用例 | 结果 |
|---|---|
| `TestDET01DiagStableAcrossRuns`（多错误源 200 轮） | PASS |
| `TestDET01DiagIndependentOfMapOrder`（歧义诊断顺序） | PASS |

### b. 运行结果稳定

| 项 | 实测 |
|---|---|
| `TestDET01RuntimeStable`（解释路径 10 轮） | PASS |
| `TestDET01EmitCDeterministic`（EmitC 5 次逐字节） | PASS |
| 同一 `-o` 两次构建 sha256 | `fb4e4f45…933f` = `fb4e4f45…933f`，**一致** |
| 编译路径 10 次运行 stdout sha256 | `6319d98b…c2b3`（10/10 同一值） |
| 解释路径 10 次运行 stdout sha256 | `6319d98b…c2b3`（10/10 同一值） |
| 跨路径对比 | 两侧同一 sha256，逐字节一致 |
| 9 示例双路径 | **9/9 MATCH**（stdout + rc） |

被测源：`examples/containers.x`。

### c. 初始化顺序与文件创建顺序无关

`TestDET01InitOrderIndependentOfCreationOrder`：同一逻辑树按 20 种文件创建顺序落盘，合并声明序与运行输出逐字节一致。PASS。

---

## 三、边界 / 风险

1. **不同 `-o` 名**：同命令两次构建到不同输出路径，产物仅 **16 字节** 不同（Mach-O `LC_UUID`），文件长度相同；内容差异限于 UUID。若 CI 要落产物 sha 锚点，须固定输出路径。
2. 编译路径 10 次运行由 CLI 证据覆盖，未写成 Go 测试（每轮 cc 约 3s，10 轮过慢）。
3. 多包 / 工程清单模式的确定性未覆盖（PKG-01 / ENTRY-01 范围）。
4. 浮点/时间等外部输入未纳入本轮；本锚点只验同源、同版本、同选项。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./...` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 计数 13（golden 10）。由 `status.tsv` 的 GEN/NEG/PKG 翻 PASS 引起，与 DET-01 无关，需另修 golden 或回退状态。 |
| `go vet ./...` | exit 0 |

---

## 五、证据

- 复验目录：`evidence/M1-DET-01-reverify-d620ea5/`
  - `det01.log`：5 个 DET 用例
  - `sha.txt`：被测 sha、两次构建 hash、10 次运行 hash
  - `compiled-10-runs.txt`、`interp-10-runs.txt`
  - `dualpath-9.txt`：9 示例双路径
  - `command.txt`
- 被测 sha：main `d620ea5`
- 断言依据：台账 DET-01 三项；`XNull解决方案-第1部分-基础语法-v3.3.0.md` §13 DET-01
