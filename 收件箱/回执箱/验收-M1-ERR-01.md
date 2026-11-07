# 验收：M1-ERR-01（错误处理，S1 §10）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（12/12；QA 独立用例 sema/interp 全绿）
> **复验点**：main `d620ea5`
> **时间**：2026-11-07

---

## 一、结论

| 项 | 结果 |
|---|---|
| QA 独立 sema 用例（正例 + 负例） | **PASS**，0 FAIL |
| QA 独立 interp 用例 | **PASS**，0 FAIL |
| B1 闭包 `try` 失败穿透外层函数 | **已闭环**（三行输出正确） |
| B2 清理体单条局部声明诊断位置 | **已闭环**（`2:11`，非 `0:0`） |
| 既有 ERR-01 / interp 运行期用例 | **PASS** |
| 台账 12 项验收要点 | **PASS 12/12** |

**判定：PASS。** 上一轮 FAIL 的 B1/B2 在 main 上均已修复；残留的 1 项为 QA 测试期望顺序错误，已按 S1 §10.3 修正测试（不改实现）。

---

## 二、台账 12 项逐项

| # | 台账要点 | 实测 | 判定 |
|---:|---|---|---|
| 1 | `Result` 构造 | `Ok`/`Err` 目标类型、`Ok()` 仅 void、`E≠void`、无目标 `ERR-202` | PASS |
| 2 | `Result` 成员 | `isOk/isErr/value/error` 无参、`unwrapOr` 一参、void 成员、未知成员 | PASS |
| 3 | `@mustUse` | 裸变量/裸调用/裸 `Ok`/defer 内未处理 → `ERR-201`；赋值/返回/容器/成员调用合法 | PASS |
| 4 | `try` 传播 | 仅 Result、外层 Result、`E→E2`、void 语句、嵌套、main/ctor/deinit/defer 禁用、闭包目标 | PASS |
| 5 | 错误类型检查 | `E≠void`、两实参、Ok/Err 实参匹配、`E→E2` 同型/`Object`/`Any` | PASS |
| 6 | `defer`/`errdefer` LIFO | `TestErrReturnRunsDeferAndErrdeferLIFO`、`TestOkReturnSkipsErrdefer`、`TestThrowSkipsDefer` | PASS |
| 7 | 触发条件 | 错误返回触发 `errdefer`；Ok/break/continue/throw 路径正确；非 Result 函数/闭包 `ERR-206` | PASS |
| 8 | 清理体限制 | return/break/continue/goto/try/throw/嵌套 defer/errdefer/闭包/单条局部声明 → `ERR-205` | PASS |
| 9 | `isOk` 正确使用 | 正向 + arity/返回 Bool/未知成员负例 | PASS |
| 10 | `isErr` 正确使用 | 同上 | PASS |
| 11 | `value` 正确使用 | 正向 + `Result<void,E>` 禁用 + arity + 运行期 `Err.value()` panic | PASS |
| 12 | `error` 正确使用 | 正向 + 运行期 `Ok.error()` panic | PASS |

命令：

```bash
go test ./internal/sema   -run 'TestQAERR01' -count=1 -v   # PASS
go test ./internal/interp -run 'TestQAERR01' -count=1 -v   # PASS
go test ./internal/sema   -run 'TestERR01'   -count=1 -v   # PASS
go test ./internal/interp -run 'TestErr|TestResult|TestThrow' -count=1 -v  # PASS
```

---

## 三、B1 / B2 闭环

### B1 闭包 `try` 失败从闭包返回

`probes/closure-try2.x`（解释路径）：

```
closure-err:bad
after-call
outer-ok
```

rc=0，无 `outer-err`，无外层 `errdefer` 误触发。**PASS。**

### B2 清理体单条局部声明诊断位置

```x
static Result<Int, String> f() {
    defer Int x = 1;
    return Ok(1);
}
```

`xnull build` 实测：

```
cleanup-localdecl.x:2:11: error[ERR-205]: defer/errdefer 的单条语句体不得是局部声明（§10.3）
```

rc=1，位置为 `2:11`（原 `0:0`）。**PASS。**

---

## 四、测试期望修正（不改实现）

上一轮 QA interp 用例「闭包 try 失败不触发外层 errdefer」期望为：

```
... after-call, outer-ok, outer-d
```

按 S1 §10.3，`defer` 在当前作用域退出时执行。`f` 的 `outer-d` 在 `f` 返回时执行，早于 `main` 的 `outer-ok`，故正确期望为：

```
closure-e
closure-d
handled
after-call
outer-d
outer-ok
```

该期望已在 `evidence/M1-ERR-01-qa/qa/qa-interp-test.go.txt` 中修正并注明依据（main 已含）；本轮未改任何实现代码，复跑为 **PASS**。

---

## 五、回归与边界

| 项 | 结果 |
|---|---|
| `go test ./internal/sema ./internal/interp` | 两包 ok |
| `go test ./...` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 计数 13（golden 10）。由 `status.tsv` 的 GEN/NEG/PKG 翻 PASS 引起，与 ERR-01 无关，需另修 golden 或回退状态。 |
| `go vet ./...` | exit 0 |

未覆盖 / 边界（沿用原验收口径）：

1. `E → E2` 的类/协议子类型可赋值：依赖 TYPE-01 子类型规则，当前仅同型/`Object`/`Any`。
2. 无目标类型的闭包内 `try`：仅当闭包赋给函数类型目标时检查函数体。
3. 编译路径的闭包 `try`：受 codegen 闭包支持面限制，本轮只验解释路径。
4. 构造器 / `deinit` 内的 `try`：RD 有 sema 用例，本轮未独立重跑。
5. 变异 / 覆盖率不属本卡。

---

## 六、证据

- 复验目录：`evidence/M1-ERR-01-reverify-d620ea5/`
  - `qa-sema.log`、`qa-interp.log`：QA 独立用例（0 FAIL）
  - `rd-sema.log`、`rd-interp.log`、`lifo.log`：既有用例与 LIFO
  - `probes/closure-try2.{x,out,err,exit}`、`probes/cleanup-localdecl.{x,err,exit}`
  - `sha.txt`、`command.txt`
- 被测 sha：main `d620ea5`（ERR 修复 `95e1f41` 已在祖先链）
- 断言依据：`XNull解决方案-第1部分-基础语法-v3.3.0.md` §10.1–§10.4
