# 验收回执：M1-ERR-01（独立 QA）

> **验收人**：CEO1-QA1-合规
> **基线**：main `2c00cf5`（ERR-01 `09367e8` 已由 `c737099` 合入；含 DET/TYPE-01、GEN-01）
> **被测**：`impl/internal/sema/{error.go,ty.go,typedecl.go}` + `impl/internal/interp` 的 Result/defer 运行期
> **独立性**：检查表与用例按 S1 §10 自写；未引用/未修改 RD 的 `impl/internal/sema/err01_test.go`；所有运行在 rsync 副本，`wt/c1-rd2` 与原仓零写入。
> **完整报告**：`收件箱/CEO1/验收-M1-ERR-01.md`

---

## 0. 当前判定（2026-11-07 复验，main `d349f6a`）：**PASS**

- QA 独立用例 overlay 复跑：`TestQAERR01` sema **exit 0**、interp **exit 0**（0 FAIL）。
- 历史 B1/B2 已由 `evidence/M1-ERR-01-fix2/` 修复（main 上复验通过）。
- 残留 1 项为 **QA 测试期望顺序错误**，非实现缺陷：原期望 `... after-call, outer-ok, outer-d` 与 S1 §10.3 矛盾。已按 §10.3 修正为 `... after-call, outer-d, outer-ok`（`defer` 在当前作用域退出时执行，先于调用方继续），并在 `evidence/M1-ERR-01-qa/qa/qa-interp-test.go.txt` 注明；未改任何实现代码。
- 复现：`wt/qa-1/evidence/QA1-anchors-2026-11-07/logs/err-{sema,interp}.log`。

**结论：PASS（0 FAIL）。**

---

## 结论

**FAIL**（2 项阻塞）

| 阻塞 | 条款 | 实际 |
|---|---|---|
| **B1** 闭包内 `try` 失败穿透外层函数 | S1 §10.2（`XNull解决方案-第1部分-基础语法-v3.3.0.md:1478`） | 合法闭包程序被 sema 接受；解释器输出 `outer-err:bad`，缺少 `closure-err:bad`/`after-call`/`outer-ok`；外层 `errdefer` 被误触发 |
| **B2** 清理体“单条局部声明”诊断无位置 | S1 §10.3（`:1514`）；S9 附录 C.4（`:1228`） | 拒绝行为正确，但输出 `file:0:0: error[ERR-205]`，不是 `file:line:col`（期望第 2 行第 11 列） |

**通过面**：独立 sema 子用例 **45/46**、运行期子用例 **19/21** 通过；`go test ./internal/sema ./internal/interp`、`go test ./...`、9 示例双路径（9/9）全部 exit 0。但 9/9 与 RD 的 12/12 均未覆盖 B1，不能作为 ERR-01 全绿证据。

**与原提交关系**：`09367e8` 同样复现 B1/B2；`c737099` 合并到 main 后未修复。

---

## 已跑命令与结果

| # | 命令 | 结果 | 证据 |
|---|---|---|---|
| 1 | `go test ./internal/sema ./internal/interp -count=1 -timeout 300s` | **exit 0**；sema 2.323s、interp 1.006s | `evidence-M1-ERR-01/suite/sema-interp.{log,exit}` |
| 2 | `go test ./... -count=1 -timeout 300s` | **exit 0**；全部包 ok | `evidence-M1-ERR-01/suite/go-all.{log,exit}` |
| 3 | `go test ./internal/codegen -run 'TestExamplesCompileMatchesInterp\|TestCompileDeferSemantics\|TestMultiFileExampleCompileMatchesInterp' -count=1 -v` | **exit 0**；9/9 示例 PASS + defer + multi | `evidence-M1-ERR-01/suite/examples.{log,exit}` |
| 4 | `go test ./internal/sema -run TestQAERR01 -count=1 -v` | **exit 1**；45 PASS / 1 FAIL（B2） | `evidence-M1-ERR-01/qa/sema-acceptance.{log,exit}` |
| 5 | `go test ./internal/interp -run TestQAERR01 -count=1 -v` | **exit 1**；19 PASS / 2 FAIL（B1） | `evidence-M1-ERR-01/qa/interp-acceptance.{log,exit}` |
| 6 | `go run ./cmd/xnull run --interp probes/closure-try2.x` | **exit 0**，stdout=`outer-err:bad`（期望 3 行，见 B1） | `evidence-M1-ERR-01/probes/cli-closure-try.{out,err,exit}` |
| 7 | `go run ./cmd/xnull build probes/cleanup-localdecl.x` | **exit 1**，stderr=`<path>:0:0: error[ERR-205]` | `evidence-M1-ERR-01/probes/cli-cleanup.{out,err,exit}` |

### B1 最小复现（规范期望 vs 实际）

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

期望：`closure-err:bad` → `after-call` → `outer-ok`；实际：仅 `outer-err:bad`。定位：`impl/internal/interp/values.go:547` 的 `callClosure` 只恢复 `ctrlReturn`，`ctrlErr` 在 `:567-575` 被原样上抛，与 S1 §10.2“错误从闭包返回、不穿透外层函数”相反。

### B2 最小复现

```x
static Result<Int, String> f() {
    defer Int x = 1;
    return Ok(1);
}
static Int main() { return 0; }
```

实际：`<path>:0:0: error[ERR-205]`；期望定位到 `defer` 后的 `Int x = 1`（第 2 行第 11 列）。定位：`impl/internal/sema/error.go:402` 使用 `d.Stmt.Pos()`，`LocalDeclStmt` 返回零位置。

---

## 未跑清单

1. **构造器 / `deinit` 内的 `try`**：RD 有 sema 用例，本轮未独立重跑，不计入通过面。
2. **`E → E2` 的类/协议子类型可赋值**：RD 声明当前仅支持同型 + `Object`/`Any`，类继承/协议实现未实现；本轮未另测。
3. **无目标类型的闭包内 `try`**：RD 声明不遍历无目标闭包体；本轮未测，属剩余漏检面。
4. **编译路径的闭包 `try`**：`examples` 无闭包用例，且闭包代码生成属 P1-6 未完成面；本轮只验证解释路径。
5. **变异测试 / SKIP 审计**：未对 ERR 诊断做变异；`go test ./...` 的 SKIP 数未逐项统计，不宣称 `SKIP=0`。
6. **附带观察（不计入本卡判据）**：函数类型变量调用 `h(Ok(1))` 报 `ERR-202` 无法推断（具名函数参数 `consume(Ok(1))` 正常），更像 TYPE-01/闭包调用参数推断问题，建议另开卡。

---

## 证据路径

- 完整报告：`收件箱/CEO1/验收-M1-ERR-01.md`
- 证据根：`收件箱/CEO1/evidence-M1-ERR-01/`
  - `sha.txt`：main `2c00cf5`、原 ERR-01 `09367e8`、用例/探针 sha256
  - `command.txt`：全部可复现命令
  - `suite/`：sema+interp、全仓、9 示例
  - `qa/`：独立 sema/运行期用例与日志（`qa-sema-test.go.txt`、`qa-interp-test.go.txt`）
  - `probes/`：B1/B2 最小复现与 CLI 输出

---

## 判定与后续

**M1-ERR-01：FAIL。** 在 B1、B2 修复并复验前：

- 台账 ERR-01 不应从 `部分` 改为 `PASS`；
- RD 的 `evidence/M1-ERR-01/acceptance.md` 12/12 不能作为全绿依据；
- 9/9 示例双路径只证明既有示例一致，不证明 §10.2 闭包语义。

修复后原样重跑：

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
