# 回执-S2-E3-super

1. 改了什么：新增 `impl/internal/interp/super.go`——`superBase` 按当前实例方法声明类的父类起查；`superField` 在父类链读写字段。`interp.go` 接入 `super.m(...)`（从父类起点静态选方法）、`super.field` 读写；`objects.go` 的 `callMethod` 拆出 `callMethodFrom(start,...)`，并用 `methodStack` 记录方法声明类（多级 super 的起点正确）。新增 `s2_super_members_test.go`（4 子例）。
2. 先红后绿：红 `evidence/S2-E3d/red.log` 4/4 FAIL（全部 `未定义的名称：super`）；绿 `green.log` 4/4 PASS（super 方法、字段读、字段写、三级继承）。
3. main 落点：分支 `pod/e3-interp@d3aeb69` → main `d3aeb69`（fast-forward）。CLI `--interp`：`super.x = super.x+1; return super.f()+super.x` 输出 `14/4`（`evidence/S2-E3d/super.x`、`cli.out`）。
4. 回归：`go test ./internal/interp/...` ok；`go vet ./...` 0；`go test ./...` 唯一失败仍为既有 `devtool/TestBuildLedgerRepoGoldenScale`（与本卡无关）。
5. 边界：`super` 仅在实例方法内可用；静态方法/字段初始化中的 super 仍会显式失败（sema 应拒绝）；`super.m()` 按静态起点查找，不改变实例方法运行的 self。
6. 是否越界：否（只改 `impl/internal/interp/**` + `evidence/S2-E3d/**`；未 push）。
