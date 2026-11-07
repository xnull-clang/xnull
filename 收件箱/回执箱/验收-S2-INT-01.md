# 验收：S2-INT-01（Result / try / defer × 对象 / 工厂 / 枚举）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（解释路径部分通过；CLI 端到端与编译路径三项均不通过）
> **复验点**：main `47fedb8`（`47fedb8ad1659925af04a677a9e82b861c2dffcd`）
> **时间**：2026-11-07
> **证据**：`evidence/S2-QA/INT-01/`、`evidence/S2-QA/matrix.tsv`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `A01` Result/try/defer + class + deinit（解释） | **PASS**：`m-err/m-defer/dR/outer-defer/outer-err/caught:bad` |
| `A01` 编译路径 | **FAIL**：`codegen：try 调用目标 *xfront.Member 未支持` |
| `A02` Result/try/defer + factory（解释） | **FAIL**：CLI `RES-101`，`DeviceFactory` 未定义 |
| `A02` 编译路径 | **FAIL**：同一 `RES-101`（sema 在 codegen 前拒绝） |
| `A03` 枚举穷尽 switch × 对象（解释） | **PASS**：`g/b` |
| `A03` 编译路径 | **FAIL**：`codegen：类字段 Holder.c 的初始化式访问了成员 Green` |
| `D01` A01–A03 双路径一致 | **FAIL**：三项 compiled rc=1 |

**判定：FAIL。** 解释器内部（`interp.Run` 直跑）的三组语义通过；但 CLI 端到端与编译路径不成立。尤其 `A02`：sema 未登记 factory 名，任何使用工厂的 CLI 程序都在 `check` 阶段以 `RES-101` 失败，factory 的 interp/codegen 实现无法从命令行触达。台账 INT-01 不得改 PASS。

---

## 二、逐项实测

### 2.1 A01：Result/try/defer × class/deinit

夹具：`difftest/s2/int01/a01_result_object.x`

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=0 | 前端接受 |
| `run --interp` | `m-err\nm-defer\ndR\nouter-defer\nouter-err\ncaught:bad\n`，rc=0 | **PASS** |
| `run`（编译） | rc=1，`codegen：try 调用目标 *xfront.Member 未支持` | **FAIL** |

### 2.2 A02：Result/try/defer × factory

夹具：`difftest/s2/int01/a02_factory_result.x`

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=1，`a02_factory_result.x:16:16: error[RES-101]: 未定义的名称 \`DeviceFactory\`` | **FAIL** |
| `run --interp` | 同一 `RES-101`，rc=1 | **FAIL** |
| `run`（编译） | 同一 `RES-101`，rc=1 | **FAIL** |

最小复现：`factory DeviceFactory for Device { ... }` + `DeviceFactory.create()`，`check`/`interp`/`compiled` 三路径均 `RES-101`。

根因：`impl/internal/sema/typedecl.go:22` 明确「factory/singleton/extension … 属后续批次」；sema 未把 `FactoryDecl` 名登记进顶层名空间。interp 与 codegen 各自有 factory 实现（`internal/interp/factory.go`、`internal/codegen/factory.go`），但 CLI 先跑 sema，工厂程序在到达解释器/代码生成前即被拒绝。

为什么 `go test ./internal/interp -run TestS2INT01` 仍 PASS：`internal/interp/s2_int01_test.go` 走 `xfront.ParseUnit` + `interp.Run`，**不经过 sema**（`internal/interp/interp_test.go:17-25`）；该测试只证明解释器内核，不证明 CLI 端到端。

### 2.3 A03：枚举穷尽 switch × 对象

夹具：`difftest/s2/int01/a03_enum_switch_object.x`

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=0 | 前端接受 |
| `run --interp` | `g\nb\n`，rc=0 | **PASS** |
| `run`（编译） | rc=1，`codegen：类字段 Holder.c 的初始化式访问了成员 \`Green\`（…字段初值不能引用 self…）` | **FAIL** |

编译路径把 `Color c = Color.Green` 的字段初始化式误判为成员访问；枚举项常量在类字段初始化式中不可用。

### 2.4 双路径

| 用例 | interp rc | compiled rc | stdout 一致 | 判定 |
|---|---|---|---|---|
| A01 | 0 | 1 | 否（compiled 无输出） | **FAIL** |
| A02 | 1 | 1 | 否（均无输出，但前端即失败） | **FAIL** |
| A03 | 0 | 1 | 否（compiled 无输出） | **FAIL** |

---

## 三、官方用例与边界

| 用例 | 结果 | 说明 |
|---|---|---|
| `internal/interp/s2_int01_test.go:TestS2INT01ResultTryObject` | **PASS** | 解释器内核；不经过 sema |
| `internal/interp/s2_int01_test.go:TestS2INT01FactoryResult` | **PASS** | 同上；CLI 端到端失败 |
| `internal/interp/s2_int01_test.go:TestS2INT01EnumSwitchObject` | **PASS** | 同上；编译路径失败 |

INT-01 是三线集成锚点（E2 sema + E3 interp + E4 codegen）。当前状态是「各自模块有实现，集成未闭合」：

- factory：E3/E4 有实现，E2 sema 未登记（`RES-101`）。
- try × 成员调用：E3 有实现，E4 codegen 未支持。
- 枚举项 × 类字段初始化式：E2/E3 接受，E4 codegen 未支持。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/interp -run 'TestS2INT01' -count=1` | **PASS**（解释器内核，非端到端） |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1 -timeout 1200s` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`（台账 PASS 13 / golden 18），与本锚点无关但阻断 GATE-01。 |

---

## 五、放行条件

1. E2：登记 factory 名与目标类型，使 `Factory.method(...)` 通过 sema（`RES-101` 消除）。
2. E4：支持 `try` 的成员调用目标（`try r.get(false)`）。
3. E4：类字段初始化式支持枚举项常量（`Color c = Color.Green`）。
4. 复跑 A01–A03：interp 与 compiled 的 stdout 逐字节一致、rc=0；D01 0 mismatch。
5. 端到端用例必须走 CLI（`xnull check` / `run --interp` / `run`），不得只用 `interp.Run` 直跑替代。

---

## 六、证据

- `evidence/S2-QA/INT-01/A01/`、`A02/`、`A03/`（含 `cmd.txt`、`check.*`、`interp.*`、`compiled.*`、`sha.txt`）
- `evidence/S2-QA/qa-c-interp.log`、`qa-c-fulltest.log`、`qa-c-vet.log`
- `evidence/S2-QA/matrix.tsv`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §8.5、§10、§16 INT-01；`XNull一致性用例台账-v1.0.0.md` INT-01
