# 回执：S2-E2-BND-13/EXT-01（sema）

- **状态**：`DONE`
- **改动**：
  - `impl/internal/sema/typedecl.go`：extension 目标校验（同包 class/struct、非预定义、非泛型、非跨包）；重复 extension；与目标/继承/其他扩展同签名；子类覆写扩展方法拒绝；扩展方法仅可访问公开成员（private/protected 拒绝）。
  - 测试：`impl/internal/sema/s2_ext_test.go`（9 例）。
- **诊断**：`TY-225`（extension 规则）/`TY-203`（子类覆写扩展）。
- **红→绿**：`evidence/S2-EXT/before/sema.out` exit 1 → `after/sema.out` exit 0。
- **验证**：`go test ./internal/sema/ ./internal/xfront/ ./internal/interp/ ./internal/codegen/ -count=1` 四包全绿。
- **纪律**：仅提交 `pod/e2-sema`，未 merge main。
