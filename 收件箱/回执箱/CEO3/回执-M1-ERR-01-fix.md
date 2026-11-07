# 回执-M1-ERR-01-fix（B1：闭包内 try 穿透）

> **状态：DONE**｜commit `d1d3e11`（`pod/e3-interp`，未 push、未合并）｜只修 B1，B2（清理体诊断位置）属 sema，不在本卡。

1. 改了什么：`impl/internal/interp/values.go` 的 `callClosure` 在闭包边界把 `ctrlErr`（闭包内 `try` 失败信号）转成 `Result` 的 `Err` 值返回，不再 `panic` 穿出到外层函数；闭包级 `defer`/`errdefer` 仍由 `execBlock` 按 LIFO 正常执行。未改 sema/codegen/runtime，未改现有测试期望。
2. 怎么验（先红后绿）：红 `evidence/M1-ERR-01-fix/red.log`——原始探针输出 `outer-err:bad`，两子例 FAIL；绿 `green.log` 两子例 PASS，CLI 探针 `cli-interp-after.out` 输出 `closure-err:bad / after-call / outer-ok`（exit 0）。新增测试 `TestClosureTryReturnsFromClosure`（NoPenetration + OuterErrdeferNotTriggered）。
3. 回归：`go test ./internal/interp/...` ok（`interp-full.log`）；`go test ./... -count=1 -timeout 600s` 全部 ok（`go-test-all.log`，含 codegen 双路径与 9 示例）。
4. 证据：`wt/e3-interp/evidence/M1-ERR-01-fix/`（`closure-try2.x`、`red.log`、`green.log`、`cli-interp-after.out/.err`、`interp-full.log`、`go-test-all.log`）；本回执 `收件箱/回执箱/CEO3/回执-M1-ERR-01-fix.md`。
5. 未测项/风险：B2（`defer` 单条局部声明诊断 `file:0:0`）仍在 sema 侧，未处理；闭包内 `try` 的错误类型静态检查仍由 sema 负责，本次只修运行期传播方向。
6. 是否越界：否（仅 `impl/internal/interp/**` + `evidence/M1-ERR-01-fix/**`；提交仅 `pod/e3-interp`）。
