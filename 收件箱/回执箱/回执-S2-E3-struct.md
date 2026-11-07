# 回执-S2-E3-struct

1. 改了什么：新增 `impl/internal/interp/structs.go`（structv 值表示、`newStruct` 构造、主/普通构造器、字段初值、结构体方法与 self 槽、嵌套/可空字段）；`interp.go`/`values.go`/`objects.go` 接入 `vStruct`（零值、成员读写、方法调用、`==/===` 逐字段、类型匹配、`new` 分派）；`cloneTupleValue` 扩展为递归复制 struct（赋值/传参/返回/容器均复制，§3.3）。新增 `s2_struct_test.go`（3 子例）。
2. 先红后绿：红 `evidence/S2-STRUCT/red.log` 3/3 FAIL（`未定义的类：Point/Outer`）；绿 `green.log` 3/3 PASS（复制独立、嵌套+`Int?` 可空字段、嵌套复制独立）。
3. main 落点：分支 `pod/e3-interp@340f191` → main 合并 `bc6dc07`。QA 夹具 `--interp`：A01 `1/10/3/12`、A02 `1/5`、BND-11 A01 同 A01（`cli-*.out`），与 compiled 一致。
4. 回归：`go test ./internal/interp/...` ok；9 示例双路径 ok；`go vet ./...` 0；`go test ./...` 唯一失败为既有 devtool 台账 golden。
5. 边界：struct 写入方法通过共享接收者槽生效；嵌套 struct/元组按值深复制；结构体静态成员与数据枚举互操作未在本卡展开。
6. 是否越界：否（只改 `impl/internal/interp/**` + `evidence/S2-STRUCT/**`；未 push）。
