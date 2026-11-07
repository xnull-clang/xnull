# 回执-S2-E3-dispatch

1. 改了什么：新增 `impl/internal/interp/dispatch.go`——`scope.typeOf` 取接收者声明类型；`dispatchCall` 区分：协议静态类型先校验方法属于协议（含继承协议），再按运行时实际类动态派发；类类型/`self` 从声明类起点静态派发；`Any`/`Object`/表达式动态回退。`interp.go` 的实例方法调用改走 `dispatchCall`，裸 `self.m()` 也改为按当前声明类静态派发。新增 `s2_dispatch_test.go`（4 子例）。
2. 先红后绿：红 `evidence/S2-E3e/red.log` 2/4 FAIL（类静态变量调派生类独有方法被接受；协议变量调协议外方法被接受）；绿 `green.log` 4/4 PASS（协议动态 One/Two 得 1/2、类静态继承、类静态拒绝派生独有、协议拒绝协议外）。
3. main 落点：分支 `pod/e3-interp@6d2d636` → main `6d2d636`（fast-forward）。CLI `--interp`：`dispatch.x` 输出 `1/2/7`；9 示例双路径 PASS（`examples.log`）。
4. 回归：`go test ./internal/interp/...` ok；`go test ./internal/codegen -run TestExamplesCompileMatchesInterp` ok；`go vet ./...` 0；`go test ./...` 唯一失败为既有 `devtool/TestBuildRepoGoldenScale`（与本卡无关）。
5. 边界：静态类型仅来自变量/参数/字段的声明类型（`defineTyped`）；`Any`/`Object` 接收者仍动态回退（sema 要求先 as）；类继承本身无覆写，静态/动态差异只在“派生独有方法/协议外方法”这类负例上可观察。
6. 是否越界：否（只改 `impl/internal/interp/**` + `evidence/S2-E3e/**`；未 push）。
