# 回执：S4 OBS-01 mapErr 顶层函数

- **状态**：`DONE`（sema）
- 修复：`mapErr(r, conv)` 允许顶层函数作为转换实参；按 `(E1)->E2` 校验参数类型与返回类型；无匹配签名仍 `ERR-207` 带位置。
- 测试：`impl/internal/sema/s4_maperr_test.go`（正例 `String conv(String)`，负例 `Int conv(Int)`）。
- 红→绿：`evidence/S4-MAPERR/`；四包测试全绿。
- 边界：仅 sema；`mapErr` 运行时执行/错误值映射由 E4/E5 落地。
