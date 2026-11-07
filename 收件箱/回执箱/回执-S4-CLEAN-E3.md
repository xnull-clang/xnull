# 回执-S4-CLEAN-E3

1. 改了什么：`interp.go`/`objects.go`/`statics.go`/`structs.go`/`factory.go`/`values.go`——函数/方法/构造器/闭包/工厂方法绑定对象参数时纳入强持有（`takeOwnership`），参数在调用作用域退出时释放，临时实参（如 `f(new R())`）按 ARC 语义在调用结束执行 deinit；补齐 CLEAN-01 的“补偿失败可观测但不覆盖原错误”与对象生命周期组合。新增 `s4_clean_test.go`（E4 S4-05 CLEAN-01 原用例 + 补偿失败 + 多步状态作用域语义）。
2. 先红后绿：红 `evidence/S4-CLEAN/red.log` — 补偿失败用例缺 `dR`（参数对象未释放）、多步循环用例期望修正；绿 `green.log` 3/3 PASS。E4 CLEAN-01 原序列解释输出 `work/close:b/close:a/err:boom/1/0/fail/inner-e/outer-e/true`，与 E4 编译侧期望逐行一致（`interp.out`）。
3. 合同核对：`errdefer` LIFO 补偿、Ok 路径不补偿、`try` 逐层触发各层 `errdefer`、补偿自身 `Result` 失败仅观测不覆盖原错误；部分完成回滚（`tx` 两步 inc/dec）状态归零；循环体内 errdefer 随该轮块正常结束失效（S1 §10.3），已在用例中按规范断言。
4. 回归：`go test ./internal/interp/...` ok；9 示例双路径 ok；`go vet ./...` 0；`go test ./...` 唯一失败为既有 devtool 台账 golden。当前分支编译路径对 CLEAN 用例仍报 codegen `unwrapOr 返回类型不可判定`（E4 范围，分支尚未合 main 的新 codegen），故双路径比对以 E4 已签的 `s4_05_test.go` 期望为 oracle。
5. 边界：参数强持有只覆盖 vObj；struct/值类型不参与 deinit；容器元素/Result 载荷引用计数未在本卡扩展。
6. 是否越界：否（只改 `impl/internal/interp/**` + `evidence/S4-CLEAN/**`；未 push）。
