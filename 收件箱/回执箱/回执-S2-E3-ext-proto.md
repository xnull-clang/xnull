# 回执-S2-E3-ext-proto

## 卡1：extension 方法（BND-13 / EXT-01）— `edaf496`

1. 改了什么：`interp.go` 登记 `ExtensionDecl`（target → 方法集合）；`statics.go` 的类方法查找在继承链每层追加该目标的扩展方法（子类继承）；`structs.go` 的 struct 方法查找追加扩展；singleton/数据枚举走合成 ClassDecl 的同一路径。新增 `s2_ext_test.go`（class/struct/singleton/数据 enum 四目标）。
2. 先红后绿：红 `evidence/S2-E3-ext/red.log` 4/4 FAIL（`该类型没有成员方法`）；绿 `green.log` 4/4 PASS（`L:x`、`6`、`4`、`true/false`）。
3. 回归：`go test ./internal/interp/...` ok。CLI 仍受 sema 未注册 extension 影响（`RES-101`，E2 域）。
4. 边界：扩展不进入协议 vtable；扩展只能加实例方法（parser/sema 拒绝其余形态）。

## 卡2：PROTO-01 协议强持有 — `f9a9231`

1. 改了什么：`objv` 增强持有计数/转交标记；`interp.go` 在局部声明、重新赋值、返回处维护所有权；`deinit.go` 作用域退出按变量逆序 release、归零才 deinit；`objects.go` 字段写入维护强持有，对象 deinit 后释放字段引用。新增 `s2_proto_hold_test.go`（返回值强持有、字段强持有、A02 全序列）。
2. 先红后绿：红证据 `evidence/S2-E3-proto/red-a02-interp.out`（QA 原测：`make()` 返回即 `dC`）；绿 `green.log` 3/3 PASS，A02 输出 `7/7/dC/7/dC/dC/dC` 与 compiled 逐字节一致；返回值 `7/after/dC`、字段 `7/after/dC`。
3. 回归：`go test ./internal/interp/...` ok；9 示例双路径 ok；`go vet ./...` 0；`go test ./...` 唯一失败为既有 devtool 台账 golden。
4. 边界：所有权模型覆盖局部变量/赋值/返回值/引用字段；容器元素/Result 载荷的引用计数未在本卡扩展；协议字段 deinit 由持有对象释放字段时触发（GC 时序按解释器确定性口径）。

## 纪律

- 两个 commit 均只在 `pod/e3-interp`（`edaf496`、`f9a9231`）；未 merge main、未 push。
- 证据：`evidence/S2-E3-ext/`、`evidence/S2-E3-proto/`；本回执 `收件箱/回执箱/回执-S2-E3-ext-proto.md`。
