# 回执：S2-E2-PROTO-01（sema 面）

- **状态**：`DONE`
- **改动**：
  - `impl/internal/sema/ty.go`：`canAssign` 补 `null → class/protocol` 引用规则；协议变量赋值/父协议转换走层次检查。
  - 协议实现检查与协议成员限制沿用 BND-05：缺/错签名、父协议、非公开实现、协议变量只调协议方法（`TY-208/211`）。
  - 测试：`impl/internal/sema/s2_proto_test.go`（null、类→协议、协议→父协议、缺父协议方法、协议外方法、协议字段 GC 强持有）。
- **红→绿**：`evidence/S2-PROTO/before/sema.out`（null→P 报 TY-103）→ `after/sema.out` exit 0。
- **验证**：`go test ./internal/sema/ ./internal/xfront/ ./internal/interp/ ./internal/codegen/ -count=1` 四包全绿。
- **边界**：is/as 未动（E3）；协议强持有仅验证 sema 策略判定为 GC，运行期生命周期归 E5。
