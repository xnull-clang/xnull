# 回执-S2-E3-deinit

1. 改了什么：新增 `impl/internal/interp/deinit.go`——作用域 `owned` 记录本层声明的对象，`execBlock` 退出时按声明逆序执行 `deinit`（在 defer 之后）；`runDeinitFrom` 执行派生类 `deinit` 后自动补父类链，体内 `super.deinit()` 则接管剩余父类链（`deinitFrames` 标记，§6.4）；`deinit` 以对象去重，方法栈保证 `super` 起点正确。
2. 先红后绿：红 `evidence/S2-E3-deinit/red.log` 3/3 FAIL（块退出无 `dD`/`dB`）；绿 `green.log` 3/3 PASS（单类作用域、显式 super.deinit、无派生 deinit 自动父链）。
3. main 落点：分支 `pod/e3-interp@5af1114` → main 合并 `bc6dc07`。QA 夹具 `--interp`：M01-single `dD/after`、M01-chain `B/D/1/dD/dB/after`，与 compiled 逐字节一致（`cli-*.out`）。
4. 回归：`go test ./internal/interp/...` ok；9 示例双路径 ok；`go vet ./...` 0；`go test ./...` 唯一失败为既有 devtool 台账 golden。
5. 边界：解释器按作用域确定性触发，不模拟 ARC 计数时序（与既有 objects.go 边界一致）；对象重新赋值/容器持有不在本卡覆盖；进程退出不保证 deinit。
6. 是否越界：否（只改 `impl/internal/interp/**` + `evidence/S2-E3-deinit/**`；未 push）。
