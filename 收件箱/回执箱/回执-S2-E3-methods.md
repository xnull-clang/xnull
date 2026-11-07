# 回执-S2-E3-methods

1. 改了什么：新增 `impl/internal/interp/statics.go`——实例方法候选按继承链收集（`findMethods`）、按实参个数+类型可赋性+具体性打分选择（`selectMethod`）、静态字段零值登记/按类声明序初始化/类型名读写、静态方法查找与调用（子类同名静态方法隐藏父类）、静态上下文裸静态名解析；`objects.go` 的 `callMethod` 改用重载选择；`interp.go` 接入 `Class.field`/`Class.method()` 与静态上下文裸名。新增 `s2_methods_test.go`（5 子例）。
2. 先红后绿：红 `evidence/S2-E3c/red.log` 5/5 FAIL（按类型/按元数/继承重载均错选首方法；`C.n`/`A.f()` 报“未定义的名称”）；绿 `green.log` 5/5 PASS。
3. main 落点：分支 `pod/e3-interp@f3f9917` → main `f3f9917`（fast-forward）。CLI `--interp` 端到端 `methods.x` 输出 `2/3/4/6`（实例重载 + 静态字段 + 静态方法）。
4. 回归：`go test ./internal/interp/...` ok；`go vet ./...` 0；`go test ./...` 唯一失败仍为既有 `devtool/TestBuildLedgerRepoGoldenScale`（台账 PASS 数与 golden 不符，与本卡无关）。
5. 边界：运行时重载以实参动态类型选择；静态分派/编译期歧义诊断仍由 sema 负责。`super.method()` 未包含（按卡面后置）；静态字段不支持数据枚举（本卡范围外）。
6. 是否越界：否（只改 `impl/internal/interp/**` + `evidence/S2-E3c/**`；未 push）。
