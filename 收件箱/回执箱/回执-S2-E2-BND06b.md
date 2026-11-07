# 回执：S2-E2-BND06b（数据枚举不可变）

- **卡片**：BND-06 补口 — 数据枚举项单例/不可变
- **状态**：`DONE`
- **改动**：
  - `impl/internal/sema/ty.go`：外部 `Status.Ready.code = ...` 报 `TY-218`；`new 数据枚举项/数据枚举类型` 报 `TY-218`。
  - `impl/internal/sema/typedecl.go`：数据枚举方法体写字段报 `TY-218`；构造器内初始化仍允许；字段读取不受影响。
  - 测试：`impl/internal/sema/s2_enum_immutable_test.go`。
- **红→绿**：`evidence/S2-BND06b/before/sema.out` exit 1 → `after/sema.out` exit 0。
- **验证**：`go test ./internal/sema/ ./internal/xfront/ ./internal/interp/ ./internal/codegen/ -count=1` 四包全绿。
- **边界**：仅 sema 静态面；数据枚举项全局单例身份/GC 根属 E4/E5。
