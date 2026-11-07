# 回执-S2-E3-ctor-field

1. 改了什么：`impl/internal/interp/objects.go` 的 `evalNew` 按参数个数选择显式构造器（`Ctors`）或头部主构造器，参数求值一次，字段初始化式后执行构造器体；新增 `selfField`/`writeSelfField`，`interp.go` 的标识符读取与赋值在局部/参数未命中时回退到 `self` 字段（S2 §5.8）。新增 `s2_ctor_field_test.go`（6 子例）。未改既有测试期望。
2. 先红后绿：红 `evidence/S2-E3b/red.log` 6/6 FAIL（`E(){}` 输出 1、`D(Int x)` 报“没有带参构造器”、裸字段 `未定义的名称：x/a`）；绿 `green.log` 6/6 PASS（无参/带参/按元数重载/初值先于构造体；裸字段读写/字段初值）。
3. main 落点：分支 `pod/e3-interp@fe92213` → main `4e57bdc`。CLI `--interp`：`ctor-field.x` 输出 `7/8`（`constructor` 设值 + 裸字段自增），`evidence/S2-E3b/cli.out`。
4. 回归：`go test ./internal/interp/...` ok；`go vet ./...` 0；`go test ./...` 唯一失败仍为既有 `devtool/TestBuildLedgerRepoGoldenScale`（台账 PASS 数与 golden 不符，与本卡无关）。
5. 边界：`super(...)`/继承构造链未做（按卡面后置）；构造器体中的 `try/return` 仍由 sema 限制；数据枚举构造器复用同一 `execCtorBody`，回归通过。
6. 是否越界：否（只改 `impl/internal/interp/**` + `evidence/S2-E3b/**`；未改 sema/codegen/runtime，未 push）。
