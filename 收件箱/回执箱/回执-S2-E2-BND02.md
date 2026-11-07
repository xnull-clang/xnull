# 回执：S2-E2-BND02（继承禁止面）

- **卡片**：S2 第二卡 — BND-02 继承禁止面
- **状态**：`DONE`
- **改动**：
  - `impl/internal/sema/ty.go`：`new` 抽象类报 `TY-210`（§2.6）。
  - `impl/internal/sema/typedecl.go`：`@Override` 标记父类同签名方法报 `TY-208`（§5.3）；继承 final/单父类/祖先同签名沿用 `TY-202/203`。
  - 测试：`impl/internal/sema/s2_bnd02_test.go`（抽象 new、final 父类、@Override 类继承、父类方法静态复用、不同参重载）。
- **红→绿**：
  - 红：`evidence/S2-BND02/before/sema.out`，exit 1（`new abstract` 无诊断）。
  - 绿：`after/sema.out`，exit 0。
- **验证**：
  - `go test ./internal/sema/ ./internal/xfront/ ./internal/interp/ ./internal/codegen/ -count=1` → 四包全绿（`after/packages.out`）。
  - 全仓 `go test ./...` 的 `devtool` 台账 golden 仍为共享 `status.tsv` 存量（PASS 13 vs 期望 10），与本卡无关。
- **边界**：父类方法静态复用仅 sema 接受；运行期/编译期派发行为属 DISP-01/BND-03。构造器可见性未纳入 BND-02。
