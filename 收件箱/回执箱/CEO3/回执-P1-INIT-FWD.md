# 回执-P1-INIT-FWD（main 既有缺陷：顶层字段前向引用）

> **状态：DONE**｜main 基线 `9f5f66c`｜同步合并 `48b3619`｜修复 commit `3bdb7c5`
> **集成续**：main `49cbb27` 合并入 `pod/e3-interp` 为 `37cbe18`（冲突文件 `interp.go`/`values.go`：保留 BLD-01 `defineTyped`/容器增量 + P1 两遍 Run，未整段覆盖）；复测全绿。未 push、未合 main。

1. 改了什么：`impl/internal/interp/interp.go` 的 `Run` 改为两遍——第一遍登记全部顶层函数/类并为顶层字段预置零值，第二遍按声明顺序求值初始化式并写回；读未初始化字段得到零值，前向引用具名函数也可解析（S1 §4.3）。
2. 怎么验（先红后绿）：红 `evidence/P1-INIT-FWD/red.log` 3/3 FAIL（`未定义的名称：b`、`未定义的函数：twice`）；绿 `green.log` 3/3 PASS（直接前向、链式读零值、前向函数）。
3. 双路径：`evidence/P1-INIT-FWD/forward.x` 的 `--interp` 与 compiled 输出均为 `1\n2`（exit 0），`interp.out` / `compiled.out` 逐字节一致。
4. 回归：`go test ./internal/interp/...` ok（`interp-full.log`）；`go test ./... -count=1 -timeout 900s` 全部 ok（`go-test-all.log`）。
5. 边界：只改 `impl/internal/interp/interp.go` + `interp_test.go`，未改既有测试期望；合并 main `9f5f66c` 时无冲突（TUPLE/BLD 支援未受影响）。
6. 是否越界：否。
