# 验收：S2-INT-01（Result / try / defer × 对象 / 工厂 / 枚举）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（`try` 成员调用已修复；工厂 + Result、枚举项类字段初始化式两条编译路径未闭合）
> **复验点**：main `e2f943c`（含 `7181fda` try 成员调用；按用户声明，本次未运行 git 命令）
> **时间**：2026-11-07
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-A2-INT-01/`、`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/qa-a2-*.log`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `A01` Result/try/defer + class + deinit（解释） | **PASS**：`m-err/m-defer/dR/outer-defer/outer-err/caught:bad` |
| `A01` 编译路径 | **PASS**：与解释逐字节一致，rc=0（`7181fda` 已修） |
| `A02` Result/try/defer + factory（前端 / 解释） | **PASS**：`check` rc=0；解释 `x/f-err/f-defer/f-caught:boom` |
| `A02` 编译路径 | **FAIL**：`Result 值类型暂支持 Int/Bool，got Device` |
| `A02b` 工厂方法返回 `Result<Int,String>`（隔离） | **FAIL**：`Result 表达式目标 *xfront.Member 未支持` |
| `A03` 枚举穷尽 switch × 对象（解释） | **PASS**：`g/b` |
| `A03` 编译路径（枚举项作类字段初值） | **FAIL**：`类字段 Holder.c 的初始化式访问了成员 Green` |
| `A03b` 同一用例去掉字段初值（隔离） | **PASS**：双路径 `g/b` |
| `D01` A01–A03 双路径一致 | **FAIL**：A02/A03 compiled rc=1 |

**判定：FAIL。** `A01` 的 try 成员调用已完整通过双路径；但 INT-01 要求的三组集成未全闭合：工厂 + `Result<T,String>` 的 codegen 不支持非 Int/Bool 载荷，工厂方法返回 Result 的调用目标未支持，枚举项作为类字段初始化式仍被 codegen 误判。台账 INT-01 不得改 PASS。

---

## 二、逐项实测

### 2.1 A01：Result/try/defer × class/deinit

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=0 | **PASS** |
| `run --interp` | `m-err\nm-defer\ndR\nouter-defer\nouter-err\ncaught:bad\n`，rc=0 | **PASS** |
| `run`（编译） | 同左，rc=0 | **PASS** |

`7181fda` 的 `TestS2INT01TryMemberCall` 与本次 CLI 双路径一致。

### 2.2 A02：Result/try/defer × factory

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=0（factory 名已由 sema 登记） | **PASS** |
| `run --interp` | `x\nf-err\nf-defer\nf-caught:boom\n`，rc=0 | **PASS** |
| `run`（编译） | rc=1，`codegen：Result 值类型暂支持 Int/Bool，got Device` | **FAIL** |

隔离 `A02b`（工厂方法返回 `Result<Int,String>`，不涉及 class 载荷）：

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` / `run --interp` | rc=0，`x/f-err/f-defer/f-caught:boom` | **PASS** |
| `run`（编译） | rc=1，`codegen：Result 表达式目标 *xfront.Member 未支持` | **FAIL** |

两个失败点独立：① `Result` 载荷只支持 `Int/Bool`；② 工厂方法（`Member` 目标）返回 `Result` 的调用表达式未支持。

### 2.3 A03：枚举穷尽 switch × 对象

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=0 | **PASS** |
| `run --interp` | `g\nb\n`，rc=0 | **PASS** |
| `run`（编译） | rc=1，`codegen：类字段 Holder.c 的初始化式访问了成员 \`Green\`（…字段初值不能引用 self…）` | **FAIL** |

隔离 `A03b`：同一 `Holder`/switch，但 `Color c;` 无字段初值，改用 `h.c = Color.Green`：

| 路径 | 实测 | 判定 |
|---|---|---|
| `run --interp` | `g\nb\n`，rc=0 | **PASS** |
| `run`（编译） | `g\nb\n`，rc=0 | **PASS** |

结论：枚举 switch 本身已集成；失败点是 E4 codegen 把 `Color.Green` 类字段初始化式误判为实例成员访问。

### 2.4 双路径

| 用例 | interp rc | compiled rc | stdout 一致 | 判定 |
|---|---|---|---|---|
| A01 | 0 | 0 | 是 | **PASS** |
| A02 | 0 | 1 | 否 | **FAIL** |
| A03 | 0 | 1 | 否 | **FAIL** |
| D01 | — | — | 三项不全是 | **FAIL** |

---

## 三、官方用例与边界

| 用例 | 结果 | 说明 |
|---|---|---|
| `internal/codegen/s2_object_test.go:TestS2INT01TryMemberCall` | **PASS** | 仅覆盖 A01 的 try 成员调用 |
| `internal/interp/s2_int01_test.go:TestS2INT01ResultTryObject` | **PASS** | 解释器内核 |
| `internal/interp/s2_int01_test.go:TestS2INT01FactoryResult` | **PASS** | 解释器内核；编译路径未覆盖 |
| `internal/interp/s2_int01_test.go:TestS2INT01EnumSwitchObject` | **PASS** | 解释器内核；编译路径未覆盖 |

INT-01 是三线集成锚点（E2 sema + E3 interp + E4 codegen）。本轮已确认：

- factory 名登记：**已修**（`check` 不再 `RES-101`）。
- try 成员调用：**已修**（A01 双路径）。
- 工厂 + `Result` 载荷 / 工厂方法 Result 调用：**未修**（E4）。
- 枚举项类字段初始化式：**未修**（E4）。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/codegen -run 'TestS2INT01TryMemberCall\|TestS2EnumSimpleAndSwitch\|TestS2EnumDataSingleton' -count=1` | **PASS** |
| `go test ./internal/interp -run 'TestS2INT01\|TestS2Enum' -count=1` | **PASS** |
| `go test ./internal/sema ./internal/interp ./internal/codegen -count=1` | **PASS**（三包全量） |
| `go vet ./internal/sema ./internal/interp ./internal/codegen` | exit 0 |

本次按“只验两项”未跑全仓 `go test ./...`。

---

## 五、放行条件

1. E4：`Result<T,String>` 支持 class/struct 等引用载荷（至少 `Device`），或明确限制并在 INT-01 用例中改用受支持载荷。
2. E4：支持工厂方法作为 `Result` 返回值的调用目标（`DeviceFactory.open(false)`）。
3. E4：类字段初始化式支持枚举项常量（`Color c = Color.Green`）。
4. 复跑 A01–A03：interp 与 compiled stdout 逐字节一致、rc=0；D01 0 mismatch。

---

## 六、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-A2-INT-01/A01/`、`A02/`、`A02b/`、`A03/`、`A03b/`（每条含 `source.x`、`cmd.txt`、`check.*`、`interp.*`、`compiled.*`、`sha.txt`）
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-A2-INT-01/matrix.tsv`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/qa-a2-sema.log`、`qa-a2-codegen.log`、`qa-a2-interp.log`、`qa-a2-targeted.log`、`qa-a2-vet.log`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §8.5、§10、§16 INT-01；`XNull一致性用例台账-v1.0.0.md` INT-01
