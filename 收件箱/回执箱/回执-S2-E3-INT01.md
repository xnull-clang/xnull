# 回执-S2-E3-INT01

1. 改了什么：新增 `impl/internal/interp/factory.go`——工厂方法按签名选重载、无 self、静态上下文执行；工厂方法内 `try` 在方法边界转 Result 返回、defer/errdefer 由 execBlock 承载；工厂可调用同工厂裸方法。`interp.go` 登记 `FactoryDecl`、接入 `Factory.method(...)` 与工厂裸方法。新增 `s2_int01_test.go`（3 组：Result/try/defer×对象+deinit、工厂×Result、枚举 switch×类方法）。
2. 先红后绿：红 `evidence/S2-E3-INT01/red.log` 2/3 FAIL——外层 defer/errdefer 顺序期望修正 1 项（实际 LIFO 正确）、工厂 `未定义的名称：DeviceFactory`；绿 `green.log` 3/3 PASS。组合输出：`m-err/m-defer/dR/outer-defer/outer-err/caught:bad`、`x/f-err/f-defer/f-caught:boom`、`g/b`。
3. main 落点：分支 `pod/e3-interp@65b4386` → main `65b4386`（fast-forward）。CLI `--interp` 已支持组合（`int-supported.x`）输出与解释器预期一致；工厂端到端被 sema 的 `RES-101` 阻断（E2 尚未把 factory 纳入名称解析），故 CLI 工厂证据保留失败输出，解释器直跑用例已绿。
4. 回归：`go test ./internal/interp/...` ok；9 示例双路径 ok；`go vet ./...` 0；`go test ./...` 唯一失败为既有 devtool 台账 golden。
5. 边界：factory 运行时已实现，但 sema 未注册 factory 名称，`xnull run --interp` 的工厂程序仍会在语义阶段失败（需 E2 接 factory）；singleton/extension 不在本卡；`try` 在 main 中的限制沿用 sema。
6. 是否越界：否（只改 `impl/internal/interp/**` + `evidence/S2-E3-INT01/**`；未 push）。
