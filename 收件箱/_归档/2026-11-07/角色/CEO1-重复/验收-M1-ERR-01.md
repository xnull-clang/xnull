# 验收：M1-ERR-01（Result / @mustUse / try / defer）

> **验收人**：CEO1-QA1-合规（一司 QA）
> **基线**：main `2c00cf5`（ERR-01 `09367e8` 已经 `c737099` 合入；含 DET/TYPE-01 修复与 GEN-01 合并）
> **被测面**：`impl/internal/sema/{error.go,ty.go,typedecl.go}` + `impl/internal/interp` 的 Result/defer 运行期
> **独立性**：检查表与用例按 S1 §10 自写；未引用、未修改 RD 的 `impl/internal/sema/err01_test.go`；未改生产代码。全部运行在 rsync 副本，`wt/c1-rd2` 与原仓零写入。
> **结论**：**FAIL**（2 项阻塞）

---

## 0. 结论

| # | 阻塞项 | 条款 | 现象 | 判定 |
|---|---|---|---|---|
| **B1** | 闭包内 `try` 失败穿透外层函数 | S1 §10.2（`XNull解决方案-第1部分-基础语法-v3.3.0.md:1478`） | 合法程序被 sema 接受，解释器却把 `Err` 从闭包直接抛到外层函数；外层继续执行被跳过，外层 `errdefer` 被误触发 | **FAIL** |
| **B2** | 清理体“单条局部声明”诊断无位置 | S1 §10.3（同文件 `:1514`）；S9 附录 C.4（`:1228`） | 拒绝行为正确，但诊断输出 `file:0:0`，不是 `file:line:col` | **FAIL** |

**通过面**：独立 sema 子用例 **45/46**、运行期子用例 **19/21** 通过；`go test ./internal/sema ./internal/interp`、`go test ./...`、9 示例双路径（9/9）全部 exit 0。但 9/9 与 RD 的 12/12 都没有覆盖 B1，不能作为 ERR-01 全绿的证据。

**与原提交的关系**：`09367e8` 上同样复现 B1/B2；`c737099` 合并到 main 后未修复这两项。

---

## 1. 逐项检查表

判据来源：台账 ERR-01 行（`XNull一致性用例台账-v1.0.0.md:26`）拆成可判定项；规范原文为 S1 §10.1—§10.3。证据均在 `收件箱/CEO1/evidence-M1-ERR-01/`。

| ID | 检查项 | 判据 | 实际 | 判定 | 证据 |
|---|---|---|---|---|---|
| QA-01 | `Result` 构造正例 | `Ok(v)`/`Ok()`/`Err(e)` 按目标类型构造；`T=void` 只允许 `Ok()`；上下文中可推断 | 赋值、返回、参数、字段、数组、`Result<void,E>` 均通过；`Ok(1)` 传给具名函数参数可推断 | **PASS** | `qa/sema-acceptance.log`：`SemaPositive/构造与成员`、`上下文-参数/字段/容器` |
| QA-02 | `Result` 构造负例 | `E=void`、实参数目/类型错误、无目标类型均拒绝，码 `ERR-202`，位置落在出错构造内 | 8/8 子用例按 `ERR-202` 拒绝；位置指向实参或类型构造 | **PASS** | 同上：`SemaNegative/E不能为void` 至 `无目标类型无法推断` |
| QA-03 | `Result` 成员正例 | `isOk()/isErr()` 返回 Bool；`value()/error()/unwrapOr()` 类型正确；`Result<void,E>` 有 `error()` 无 `value()` | `Bool b = r.isOk()`、`Int x = r.unwrapOr(0)`、`Result<void,E>.error()` 均通过 | **PASS** | 同上：`上下文-void错误成员`、`构造与成员` |
| QA-04 | `Result` 成员负例 | arity 错误、未知成员、成员未调用、`void` 上取 `value`、`unwrapOr` 参数类型错误，码 `ERR-203` | 6/6 子用例拒绝；位置落在成员访问内 | **PASS** | 同上：`成员实参过多` 至 `unwrapOr参数类型` |
| QA-05 | `@mustUse` | 裸变量/裸调用/`defer` 中未处理的 Result 拒绝（`ERR-201`）；返回、赋值、容器、成员调用合法 | 3 个负例均拒绝；`r.isOk()` 作语句合法；`Result[]` 容器合法 | **PASS** | 同上：`mustUse-*`、`上下文-容器` |
| QA-06 | `Result` 类型上下文 | 变量、参数、返回值、字段、容器、闭包均可出现 | `Result` 字段初始化/赋值、数组、具名函数参数均通过；闭包变量调用带 `Ok(...)` 实参另有观察（见 §4） | **PASS** | 同上：`上下文-*` |
| QA-07 | `try` 正例 | 同型、`String→Any`、`String→Object`、`Result<void,E>` 语句、嵌套 `try try`、前缀优先级 | 全部通过；`try inner() + 1` 解释为 `(try inner()) + 1`，运行输出 2 | **PASS** | `qa/sema-acceptance.log: try-基础与加宽/嵌套与优先级`；`qa/interp-acceptance.log: 嵌套try/try优先级` |
| QA-08 | `try` 负例 | `main`/非 Result 外层/非 Result 操作数/`E→E2` 不可赋值/清理体，码 `ERR-204` 或 `ERR-205` | 5/5 子用例拒绝；`try` 在清理体同时报 `ERR-205` 与 `ERR-204` | **PASS** | `qa/sema-acceptance.log: try不能在main` 至 `try在清理体` |
| QA-09 | **闭包内 `try`** | 失败从闭包返回，**不穿透外层函数**；闭包目标返回类型必须是 `Result` | **FAIL**：sema 接受合法闭包；解释器把 `Err` 抛到外层，外层 `errdefer` 误执行（详见 §2 B1） | **FAIL** | `qa/interp-acceptance.log`：`闭包try失败必须从闭包返回...`、`闭包try失败不触发外层errdefer`；`probes/cli-closure-try.*` |
| QA-10 | `defer`/`errdefer` LIFO 与触发 | 错误返回时 defer+errdefer 都执行、逆序；Ok/普通返回只 defer；`try` 传播、显式 `Err`、Err 变量都触发 errdefer；`break/continue` 不触发 errdefer；`throw` 不执行清理 | 6 组运行期用例全部符合；顺序 `step-e → step-d → mid-e → mid-d`；`break`/`continue` 只输出 defer | **PASS** | `qa/interp-acceptance.log`：`try逐层传播...`、`返回Err变量...`、`Ok返回...`、`break/continue...`、`throw...` |
| QA-11 | 清理体限制（功能） | `return/break/continue/goto/throw/try/defer/errdefer/闭包/单条局部声明` 全部拒绝；嵌套块同样拒绝；合法清理体零诊断 | 10/10 禁止构造均被 `ERR-205` 拒绝；嵌套 `if/while` 也被扫描；合法块体通过 | **PASS** | `qa/sema-acceptance.log: 清理体*`、`SemaPositive/清理体-合法` |
| QA-12 | **清理体局部声明的位置** | 诊断必须带 `file:line:col`，定位到 `defer` 后的声明 | **FAIL**：输出 `qa.x:0:0: error[ERR-205]`；CLI 输出 `<path>:0:0`（详见 §2 B2） | **FAIL** | `qa/sema-acceptance.log: 清理体单条局部声明`；`probes/cli-cleanup.err` |
| QA-13 | `errdefer` 上下文 | 只能出现在返回 `Result` 的函数/闭包；非 Result 函数与非 Result 闭包拒绝（`ERR-206`） | 2/2 负例拒绝；Result 函数与 Result 闭包合法 | **PASS** | `qa/sema-acceptance.log: errdefer非Result函数/闭包`、`SemaPositive/errdefer-合法位置` |
| QA-14 | `value()/error()` 误用 | `Err.value()` / `Ok.error()` 运行时 panic，退出码 134；`isOk/isErr` 安全 | 两个方向均 `code=134`，stdout 空；`isOk/isErr` 输出正确 | **PASS** | `qa/interp-acceptance.log: Err上读value.../Ok上读error.../isOk-isErr安全` |
| QA-15 | 全量回归与双路径 | sema+interp 全量 exit 0；9 示例编译↔解释逐字节一致；全仓测试 exit 0 | `sema 2.323s`、`interp 1.006s`；`go test ./...` exit 0；9/9 示例 + multi 全 PASS | **PASS**（但见 §3 覆盖缺口） | `suite/sema-interp.log`、`suite/go-all.log`、`suite/examples.log` |

**计数**：独立用例 sema 46 个子用例（45 PASS / 1 FAIL），运行期 21 个子用例（19 PASS / 2 FAIL）。失败项全部归入 B1/B2。

---

## 2. 阻塞项复现

### B1　闭包内 `try` 失败穿透外层

**规范**：S1 §10.2：`闭包内使用 try 时，错误从闭包返回，不穿透到外层函数；闭包的目标返回类型必须是 Result。`（`XNull解决方案-第1部分-基础语法-v3.3.0.md:1478`）

**最小程序**（`evidence-M1-ERR-01/probes/closure-try2.x`）：

```x
static Result<Int, String> g(Int x) { return Err("bad") }

static Result<Int, String> f() {
    Result<Int, String>(Int) h = (Int x) -> { Int v = try g(x); return Ok(v); };
    Result<Int, String> r = h(-1);
    if r.isErr() { print("closure-err:" + r.error()); }
    print("after-call");
    return Ok(1);
}

static Int main() {
    Result<Int, String> r = f();
    if r.isOk() { print("outer-ok") } else { print("outer-err:" + r.error()) };
    return 0;
}
```

**期望**（按规范推导）：闭包 `h` 内 `try g(-1)` 得到 `Err("bad")`，应**从 `h` 返回 Err**；`f` 继续执行：

```text
closure-err:bad
after-call
outer-ok
```

**实际**：

```text
outer-err:bad
```

`closure-err` 与 `after-call` 都没执行，`f` 被整体提前返回为 Err。CLI 同样复现：

```bash
go run ./cmd/xnull run --interp probes/closure-try2.x
# stdout: outer-err:bad
# exit: 0
```

**带清理的变体**证明外层 `errdefer` 被误触发：

```text
实际: closure-e → closure-d → outer-e → outer-d → outer-err
期望: closure-e → closure-d → handled → after-call → outer-ok → outer-d
```

**定位**：`impl/internal/interp/values.go:547` 的 `callClosure` 只把 `ctrlReturn` 转成返回值（`:567-575`）；`ctrlErr` 被 `panic(r)` 原样抛出，注释明确写“try/Err 信号穿出（由外层函数边界接管）”。这与 S1 §10.2 相反。闭包边界必须把 `ctrlErr` 转成 `Err` 值返回，而不是继续上抛。

**为什么 9/9 双路径没抓到**：`examples/result-try.x` 只在具名函数间传播；`examples/defer-cleanup.x` 也没有闭包 `try`。RD 的 `err01_test.go` 只有 sema 断言，不执行闭包运行期。

### B2　清理体局部声明诊断位置 `0:0`

**规范**：S1 §10.3：`defer/errdefer 的单条语句体不得是局部声明`（`:1514`）；S9 附录 C.4 要求诊断格式 `file:line:col`（`XNull解决方案-第8部分-工程配置-v5.2.0.md:1228`）。

**最小程序**（`probes/cleanup-localdecl.x`）：

```x
static Result<Int, String> f() {
    defer Int x = 1;
    return Ok(1);
}
static Int main() { return 0; }
```

**实际**：

```text
<p>/probes/cleanup-localdecl.x:0:0: error[ERR-205]: defer/errdefer 的单条语句体不得是局部声明（§10.3）
```

`sema` 层同样是 `qa.x:0:0`。拒绝行为正确，但位置丢失：无法定位到第 2 行第 11 列的 `Int x = 1`。

**定位**：`impl/internal/sema/error.go:402` 使用 `d.Stmt.Pos()`；`LocalDeclStmt` 在这里返回零位置。应改用 `defer` 语句或声明节点的带位置字段。

**影响**：负例无法断言位置；编辑器/CI 无法跳转；违反 DG-02“code+file+line+col”与 S9 C.4。

---

## 3. 回归与双路径

| 项 | 命令 | 结果 | 证据 |
|---|---|---|---|
| sema + interp 全量 | `go test ./internal/sema ./internal/interp -count=1 -timeout 300s` | exit 0；sema 2.323s、interp 1.006s | `suite/sema-interp.log` |
| 全仓测试 | `go test ./... -count=1 -timeout 300s` | exit 0；全部包 ok | `suite/go-all.log` |
| 9 示例双路径 | `go test ./internal/codegen -run 'TestExamplesCompileMatchesInterp\|TestCompileDeferSemantics\|TestMultiFileExampleCompileMatchesInterp' -count=1 -v` | exit 0；9/9 子用例 PASS；`result-try.x`、`defer-cleanup.x` 均 PASS | `suite/examples.log` |
| 独立 sema 验收 | `go test ./internal/sema -run TestQAERR01 -count=1 -v` | **exit 1**；45 PASS / 1 FAIL（B2） | `qa/sema-acceptance.log` |
| 独立运行期验收 | `go test ./internal/interp -run TestQAERR01 -count=1 -v` | **exit 1**；19 PASS / 2 FAIL（B1） | `qa/interp-acceptance.log` |

**结论**：回归面没有新破坏；失败集中在 ERR-01 的两个规范点，不是环境或偶发。

---

## 4. 未测项与边界（不隐瞒）

1. **构造器 / `deinit` 内的 `try`**：RD 有 sema 用例，我未独立重跑；本次不计入通过面。
2. **`E → E2` 的类/协议子类型**：RD 声明当前只支持同型、`Any`、`Object`，类继承/协议实现的可赋值未实现；我未另测，保持其边界。
3. **无目标类型的闭包内 `try`**：RD 声明不遍历无目标类型闭包体；我未测。这意味着“闭包内 `try`”仍可能从这里漏过，需在 B1 修复时一并加用例。
4. **编译路径的闭包 `try`**：`examples` 无闭包用例，且闭包代码生成属 P1-6 未完成面；本次只验证了解释路径。
5. **附带观察（不计入 ERR-01 判据）**：函数类型变量调用时，`h(Ok(1))` 报 `ERR-202` 无法推断（具名函数参数 `consume(Ok(1))` 正常）。这更像 TYPE-01/闭包调用参数推断问题，建议另开卡，不在本卡放行。
6. **未做变异测试 / SKIP 审计**：本轮只做独立用例与全量回归，未对 ERR 诊断做变异；`go test ./...` 的 SKIP 数未逐项统计，不宣称 SKIP=0。

---

## 5. 判定与后续

**M1-ERR-01：FAIL。** 在 B1、B2 修复并复验前：

- 台账 ERR-01 不应从 `部分` 改为 `PASS`；
- RD 的 `evidence/M1-ERR-01/acceptance.md` 12/12 不能作为全绿依据（未覆盖闭包运行期与位置断言）；
- 9/9 示例双路径只证明既有示例一致，不证明 §10.2 闭包语义。

**复验入口**（修复后原样重跑）：

```bash
cp 收件箱/CEO1/evidence-M1-ERR-01/qa/qa-sema-test.go.txt impl/internal/sema/qa_err01_accept_test.go
cp 收件箱/CEO1/evidence-M1-ERR-01/qa/qa-interp-test.go.txt impl/internal/interp/qa_err01_accept_test.go
cd impl
go test ./internal/sema -run TestQAERR01 -count=1 -v
go test ./internal/interp -run TestQAERR01 -count=1 -v
go test ./internal/sema ./internal/interp -count=1 -timeout 300s
go test ./internal/codegen -run 'TestExamplesCompileMatchesInterp|TestCompileDeferSemantics|TestMultiFileExampleCompileMatchesInterp' -count=1 -v
```

期望：前两条 exit 0（B1/B2 修复），全量与 9/9 仍 exit 0。

---

## 6. 证据清单（`收件箱/CEO1/evidence-M1-ERR-01/`）

| 文件 | 内容 |
|---|---|
| `sha.txt` | main `2c00cf5`、原 ERR-01 `09367e8`、4 个用例/探针 sha256 |
| `command.txt` | 全部可复现命令与预期 |
| `suite/sema-interp.{log,exit}` | sema+interp 全量 |
| `suite/go-all.{log,exit}` | 全仓 `go test ./...` |
| `suite/examples.{log,exit}` | 9 示例双路径 + defer + multi |
| `qa/sema-acceptance.{log,exit}` | 独立 sema 验收（45/46） |
| `qa/interp-acceptance.{log,exit}` | 独立运行期验收（19/21） |
| `qa/qa-sema-test.go.txt` | 独立 sema 用例源码（可复制为 `_test.go`） |
| `qa/qa-interp-test.go.txt` | 独立运行期用例源码 |
| `probes/closure-try2.x` | B1 最小复现 |
| `probes/cli-closure-try.{out,err,exit}` | B1 CLI 输出（`outer-err:bad`，exit 0） |
| `probes/cleanup-localdecl.x` | B2 最小复现 |
| `probes/cli-cleanup.{out,err,exit}` | B2 CLI 输出（`:0:0`，exit 1） |
