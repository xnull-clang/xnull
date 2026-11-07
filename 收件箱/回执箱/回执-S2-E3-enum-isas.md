# 回执-S2-E3-enum-isas

1. 改了什么：新增 `impl/internal/interp/enums.go`（枚举登记、简单枚举底层值、`Enum.Item` 解析、数据枚举项惰性单例构造 + 构造器体执行、协议继承判定）；`interp.go` 增 `vEnum` 值类型与格式化、`Enum.Item` 成员解析、枚举 `==/!=/===/!==` 与顺序比较；`values.go` 的 `typeMatches` 改为解释器方法，补类继承链/协议实现/数据枚举项/简单枚举的 `is`/`as` 判定。新增 `s2_enum_isas_test.go`（5 个测试）。未改既有测试期望。
2. 先红后绿：红 `evidence/S2-E3/red.log`——简单枚举/switch 报 `未定义的名称：Color`，`is Shape` 等 5 项全 `false`；绿 `enum-green.log`/`green.log` 5/5 PASS（简单枚举+switch、未知项拒绝、类/协议 is/as、as 失败、数据枚举）。
3. main 落点：分支 `pod/e3-interp@3b91328` → main `69b2591`。CLI `--interp` 端到端：`enum-simple.x` 输出 `Green/g`，`is-as-protocol.x` 输出 `true`（`evidence/S2-E3/cli-*.out`）。
4. 回归：`go test ./internal/interp/...` ok；`go vet ./...` 0；`go test ./...` 唯一失败为既有 `devtool/TestBuildLedgerRepoGoldenScale`（台账 PASS 数与 golden 不符，在 main 91c89c0 上同样失败，与本卡无关，未改台账）。
5. 边界：数据枚举默认按项名格式化，`toString()` 覆写未接（S2 §8.3 边角）；协议 vtable/类静态派发仍是按名动态解析（审计 S2-E3-07，P1 未包含在本卡）；显式构造器/`super`/裸字段名仍属后续卡。
6. 是否越界：否（只改 `impl/internal/interp/**` + `evidence/S2-E3/**`；未改 sema/codegen/runtime，未 push）。
