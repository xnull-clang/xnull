# 回执：S6-XDK-07 编译端到端

- **状态**：sema/interp `PASS`（main 快照）；compiled `BLOCKED`（codegen 缺口，已交 E4）
- **main 实测**：`xnull check` 0；`xnull run --interp` 输出与 `collections_basic.expect` 一致；`xnull run` 失败于 `codegen：可空表达式成员 pop 未支持`。
- **sema 剩余缺口**：main 当前接受 `pq.less(1, "x")`（函数类型字段实参未检查）；本分支报 `TY-101`，回归用例已补 `s6_xdk07_test.go`。
- **用例**：`tests/s6/xdk07/collections_basic.x`（19 行期望）+ `collections_nonnull.x`（E4 复现）；`impl/internal/cli/xdk07_e2e_test.go` 分 sema/interp/compiled，codegen 未支持时显式 SKIP，修复后自动断言。
- **E4 交接**：`handoff/S6-XDK07-E2E.md`，按序列出 G1 可空方法/成员、G2 `return null`、G3 `FuncTypeRef` 字段、G4 数组返回/容器成员分派；未跨域改 codegen。
- **证据**：`evidence/S6-XDK07b/`（main check/interp/compiled、less 负例、main/工作树 harness、四包+cli）。
