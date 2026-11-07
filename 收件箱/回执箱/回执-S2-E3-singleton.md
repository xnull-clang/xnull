# 回执-S2-E3-singleton

1. 改了什么：新增 `impl/internal/interp/singleton.go`——单例登记（合成 ClassDecl 复用字段/方法/静态成员）、实例在顶层/静态字段之后、`main` 之前按声明顺序构造（§9.2）、`Singleton.instance` 与单例静态成员解析；`interp.go`/`objects.go`/`values.go`/`enums.go` 接入单例名义类型、`instance` 只读、单例静态方法调用。新增 `s2_singleton_test.go`（3 组：instance 字段/方法、启动前可见、前序单例/顶层字段初始化顺序）。
2. 先红后绿：红 `evidence/S2-E3-singleton/red.log` 3/3 FAIL（`未定义的名称 AppInfo/Config/A`）；绿 `green.log` 3/3 PASS。
3. main 落点：分支 `pod/e3-interp@cfa9c62` → main `d1790fa`。解释器直跑 A01/A02 期望 `XNull/3/4`、`localhost/8080` 均通过；CLI `--interp` 仍被 sema `RES-101`（singleton 名未进名称解析）阻断，输出保留在 `evidence/S2-E3-singleton/cli-*.err`（归 E2，本卡未碰 sema）。
4. 回归：`go test ./internal/interp/...` ok；9 示例双路径 ok；`go vet ./...` 0；`go test ./...` 唯一失败为既有 devtool 台账 golden。
5. 边界：`instance` 只读在解释器显式拒绝；单例 deinit 不在进程退出执行；单例静态字段与普通静态字段同批初始化；`abstract singleton` 未拒绝（sema 域）。
6. 是否越界：否（只改 `impl/internal/interp/**` + `evidence/S2-E3-singleton/**`；未 push）。
