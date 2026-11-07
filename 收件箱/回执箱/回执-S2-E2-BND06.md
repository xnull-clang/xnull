# 回执：S2-E2-BND06（枚举 switch）

- **卡片**：BND-06 枚举 switch 穷尽性/未知项/重复
- **状态**：`DONE`
- **改动**：
  - `impl/internal/sema/ty.go`：新增 `checkEnumSwitch`（`TY-213`）。
  - `impl/internal/sema/typedecl.go`：诊断码 `TY-213`。
  - 测试：`impl/internal/sema/s2_bnd06_test.go`（穷尽、遗漏、未知、重复、default、非枚举、任意表达式 case）。
- **规则**：无 default 时必须覆盖全部项且每项一次；未知项/重复项/非 `Enum.Item` 表达式拒绝；有 default 不查穷尽；非枚举 switch 不检查。
- **红→绿**：`evidence/S2-BND06/before/sema.out` exit 1 → `after/sema.out` exit 0。
- **验证**：`go test ./internal/sema/ ./internal/xfront/ ./internal/interp/ ./internal/codegen/ -count=1` 四包全绿（`after/packages.out`）。
- **边界**：仅 sema 静态检查；数据枚举字段读取/模式匹配不在本卡。
