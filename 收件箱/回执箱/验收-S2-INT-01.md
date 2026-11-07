# 验收：S2-INT-01（Result / try / defer × 对象 / 工厂 / 枚举）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `e2f943c`（按用户声明；含 INT-01b codegen。本次**未运行任何 git 命令**）
> **时间**：2026-11-07
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-INT-BATCH4/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `A01` Result/try/defer + class + deinit（解释） | **PASS**：`m-err/m-defer/dR/outer-defer/outer-err/caught:bad` |
| `A01` 编译路径 | **PASS**：逐字节一致，rc=0 |
| `A02` `Result<Device,String>` Ok 类值 + 工厂方法返回 Result（解释） | **PASS**：`x/f-err/f-defer/f-caught:boom` |
| `A02` 编译路径 | **PASS**：逐字节一致，rc=0 |
| `A02b` 工厂成员返回 `Result<Device,String>` 隔离（解释） | **PASS**：`f-err/f-defer/f-caught:boom` |
| `A02b` 编译路径 | **PASS**：逐字节一致，rc=0 |
| `A03` 枚举项作类字段初值 + 穷尽 switch（解释） | **PASS**：`g/b` |
| `A03` 编译路径 | **PASS**：逐字节一致，rc=0 |
| `D01` A01/A02/A02b/A03 双路径一致 | **PASS**：4/4，0 mismatch |
| `R01` 工厂方法返回 `Result<Int,String>`（旧 A02b 夹具） | **PASS（预期拒绝）**：`TY-220` + 位置 |

**判定：PASS。** INT-01b 已闭合上一轮的两个 codegen 缺口：`Result<类,String>` 载荷、工厂成员返回 `Result` 的调用目标、枚举项作类字段初值。四项正例双路径逐字节一致；旧的非法 `Result<Int,String>` 工厂返回已由 sema 正确拒绝（`TY-220`），不再以 codegen 失败形式出现。台账 INT-01 可登记为 PASS。

---

## 二、逐项实测

### 2.1 A01：Result/try/defer × class/deinit

夹具：`evidence/S2-QA/QA-INT-BATCH4/A01/source.x`

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=0 | **PASS** |
| `run --interp` | `m-err\nm-defer\ndR\nouter-defer\nouter-err\ncaught:bad\n`，rc=0 | **PASS** |
| `run`（编译） | 同左，rc=0 | **PASS** |

### 2.2 A02：`Result<Device,String>` + 工厂方法

夹具：`evidence/S2-QA/QA-INT-BATCH4/A02/source.x`

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=0 | **PASS** |
| `run --interp` | `x\nf-err\nf-defer\nf-caught:boom\n`，rc=0 | **PASS** |
| `run`（编译） | 同左，rc=0 | **PASS** |

覆盖：`Result<Device,String>` Ok 载荷为 class；`DeviceFactory.open(false)` 为工厂成员返回 `Result`；`defer`/`errdefer` 顺序与 A01 一致。

### 2.3 A02b：工厂成员返回 `Result` 隔离

夹具：`evidence/S2-QA/QA-INT-BATCH4/A02b/source.x`（不调用 `create`，只调用 `DeviceFactory.open`）

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=0 | **PASS** |
| `run --interp` | `f-err\nf-defer\nf-caught:boom\n`，rc=0 | **PASS** |
| `run`（编译） | 同左，rc=0 | **PASS** |

说明：上一轮的 A02b 使用 `Result<Int,String>` 作为工厂方法返回类型；按 §10.2，工厂方法只能返回 Target/父类/协议/Object 或其 `Result` 包装，`Result<Int,String>` 不是合法工厂返回。本轮把它移到 `R01` 作为预期拒绝用例，A02b 改用合法的 `Result<Device,String>` 隔离「工厂成员返回 Result」路径。

### 2.4 A03：枚举项作类字段初值

夹具：`evidence/S2-QA/QA-INT-BATCH4/A03/source.x`

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=0 | **PASS** |
| `run --interp` | `g\nb\n`，rc=0 | **PASS** |
| `run`（编译） | `g\nb\n`，rc=0 | **PASS** |

上一轮编译失败点 `类字段 Holder.c 的初始化式访问了成员 Green` 已消失。

### 2.5 R01：非法工厂返回（旧 A02b）

夹具：`evidence/S2-QA/QA-INT-BATCH4/R01/source.x`（`static Result<Int,String> open(...)`）

| 路径 | 实测 | 判定 |
|---|---|---|
| `check` | rc=1，`source.x:8:32: error[TY-220]: factory 方法 \`open\` 返回类型 \`Result<Int,String>\` 不能归到 Target \`Device\`（§10.2）` | **PASS（预期拒绝）** |
| `run --interp` / `run` | 同一 `TY-220`，rc=1 | **PASS** |

该用例从「codegen 报 `Result 表达式目标 *xfront.Member 未支持`」变为「sema 按 §10.2 拒绝」，是正确性提升，不是 INT-01 的失败项。

### 2.6 双路径汇总

| 用例 | interp rc | compiled rc | stdout 一致 | 判定 |
|---|---|---|---|---|
| A01 | 0 | 0 | 是 | **PASS** |
| A02 | 0 | 0 | 是 | **PASS** |
| A02b | 0 | 0 | 是 | **PASS** |
| A03 | 0 | 0 | 是 | **PASS** |
| D01 | — | — | 4/4 | **PASS** |

---

## 三、INT-01b 落地确认（未用 git）

任务要求先 `git log` 确认 b2deb74，同时明确“禁止任何 git 命令”。本次遵守禁令，未运行 git；改用**源码/测试内容 + 行为**确认 INT-01b 已落地：

| 证据 | 内容 |
|---|---|
| `impl/internal/codegen/codegen.go:431` | 新增注释「Result 实例 typedef：需要类/struct/枚举的前向 typedef 先就位（INT-01b）」 |
| `impl/internal/codegen/s2_object_test.go:617` | 新增 `TestS2INT01bResultClassAndMemberTarget`（PASS） |
| `impl/internal/codegen/s2_object_test.go:646` | 新增 `TestS2INT01bEnumFieldInit`（PASS） |
| 文件 mtime | codegen/s2_object_test 于 22:30:44 更新；构建与复跑时保持稳定 |
| 行为 | 上一轮 A02/A03 的 compiled rc=1 已变为 rc=0，stdout 与 interp 一致 |

main SHA `e2f943c` 按用户声明记录；本回执不以 git 命令二次校验。

---

## 四、官方用例

| 用例 | 结果 |
|---|---|
| `internal/codegen/s2_object_test.go:TestS2INT01TryMemberCall` | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2INT01bResultClassAndMemberTarget` | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2INT01bEnumFieldInit` | **PASS** |
| `internal/interp/s2_int01_test.go:TestS2INT01ResultTryObject` | **PASS** |
| `internal/interp/s2_int01_test.go:TestS2INT01FactoryResult` | **PASS** |
| `internal/interp/s2_int01_test.go:TestS2INT01EnumSwitchObject` | **PASS** |

---

## 五、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/codegen -run 'TestS2INT01' -count=1` | **PASS**（3/3） |
| `go test ./internal/interp -run 'TestS2INT01' -count=1` | **PASS**（3/3） |
| `go test ./internal/sema ./internal/interp ./internal/codegen -count=1` | **PASS**（三包全量；codegen 150s，机器有并发负载） |
| `go vet ./internal/sema ./internal/interp ./internal/codegen` | exit 0 |

本次按“只验两项/只签 INT-01”未跑全仓 `go test ./...`。

---

## 六、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-INT-BATCH4/A01/`、`A02/`、`A02b/`、`A03/`、`R01/`（每条含 `source.x`、`cmd.txt`、`check.*`、`interp.*`、`compiled.*`、`sha.txt`）
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-INT-BATCH4/matrix.tsv`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-INT-BATCH4/codegen-int01.log`、`interp-int01.log`、`targeted.log`、`vet.log`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §8.5、§10.2、§16 INT-01；`XNull一致性用例台账-v1.0.0.md` INT-01
