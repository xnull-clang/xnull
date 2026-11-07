# 回执-S4-CLEAN-E3b

1. 改了什么：解释器为 `new` 产生的对象增加“临时持有”——登记在创建它的作用域，调用方块结束时按逆序释放；`T x = new T()` / `x = new T()` 把临时引用转交变量，避免重复持有。因此 `g(new R())` / `f(new Comp(), new R())` 的临时实参在被调方 `errdefer`、错误返回与调用方错误处理之后才 deinit，与 compiled 顺序一致。另按 S4-OBS-01 裁定把 `report` 诊断改为 `[Kind] describe`，并改为返回 `void`（链式写法删除）。
2. 先红后绿：红 `evidence/S4-CLEAN/red2.log` —— `clean-param` 输出 `dR/err:x`、补偿组合 `comp/dR/err`；绿 `green.log` / CLI：`clean-param` → `err:x/dR`，`clean2` → `comp:comp-fail/err:orig/dR`。`report` CLI stderr → `[Io] disk`（`evidence/S4-02/cli.err`）。
3. 回归：`go test ./internal/interp/...` ok；9 示例双路径 ok；`go vet ./...` 0；`go test ./...` 唯一失败为既有 devtool 台账 golden。既有 `TestS2ProtocolStrongHold/A02Alignment` 顺序保持 `7/7/dC/7/dC/dC/dC`。
4. 边界：临时生命周期按创建作用域（块）释放，与 compiled 的块级临时存储一致；容器元素/Result 载荷的临时持有仍不在本卡范围。
5. 是否越界：否（只改 `impl/internal/interp/**` + `evidence/S4-CLEAN|S4-02/**`；未 push）。
