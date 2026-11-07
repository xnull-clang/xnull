# 接力棒：GEN-01

- **卡片ID**：GEN-01（S1/M1，前端线 E2 独占；含 sema 与 codegen 集成）
- **输入**（上游产物/条款/接口）：
  - 台账 `XNull一致性用例台账-v1.0.0.md:27` GEN-01
  - `XNull解决方案-第1部分-基础语法-v3.3.0.md` §8.1–§8.4
  - 检查表：`evidence/M1-GEN-01-sema/checklist-source.md`
  - 历史红源：`evidence/M1-GEN-01-sema/before/`（24 FAIL，卡在 sema TY-101）
  - main 已合入的 sema 泛型：`impl/internal/sema/generic.go`
- **输出文件**（精确路径）：
  - `impl/internal/sema/generic.go`、`gen01_test.go`、`gen01_extra_test.go`、`gen01_crossfile_test.go`
  - `impl/internal/codegen/generics.go`（单态化实例展开）
  - `impl/internal/codegen/codegen.go`、`types.go`（实例调用/类型替换/is 静态判定）
  - `impl/internal/codegen/gen01_acceptance_test.go`（26 项权威检查表）
  - `impl/internal/codegen/gen01_mono_test.go`
- **commit**：`20e3d838ea45`（GEN-01 集成提交）；main 合并后 HEAD `131c2449fb14`；证据：`evidence/M1-GEN-01/e2-final/`（26/26 原始日志 + acceptance）
- **验证命令**（可复制）：
  ```bash
  cd impl
  go test ./internal/codegen/ -run 'TestGEN01' -v -count=1   # 26/26 PASS + CrossFile
  go test ./internal/sema/ -run 'TestGEN01' -v -count=1
  go test ./... -count=1 -timeout 300s
  ```
  结果：GEN-01 26/26 PASS（0 FAIL / 0 SKIP）；全仓 exit 0。
- **已知缺口/风险**：
  - G9 签名位置泄漏已修（`static T g(T x)` → `RES-101`，commit `c55dd8151645`）。
  - G7 当前验收走“直接自递归 sema 诊断”；嵌套 `grow<List<T>>` 的源码级用例仍受 xfront `>>` 拆分（EXP-008）限制，未在本卡展开。
  - G12 以“泛型函数作为值 → 解析拒绝”验收；诊断质量仍为 SYN-102 级联，属 xfront。
  - codegen 实例命名/展开上限沿用 `maxInstDepth=64`；跨包泛型实例仅验证到 `LoadUnits` 合并后可见。
  - `status.tsv` 未手改；由 QA/SSOT 按端到端结果翻状态。
- **下一步**（谁接、做什么）：
  - **谁接 1（当前）**：QA1 独立验收；通知已投 `收件箱/QA1/请求-GEN-01独立验收.md`。
  - **做什么**：用独立用例复跑 GEN 26 项（不得复用本表期望），核对 `evidence/M1-GEN-01/e2-final/`；通过后由 SSOT 将 GEN-01 翻 PASS（M1 7/14）。
  - **验证命令**：
    ```bash
    cd impl
    go test ./internal/codegen/ -run 'TestGEN01' -v -count=1
    go test ./internal/sema/ -run 'TestGEN01' -v -count=1
    go test ./... -count=1 -timeout 300s
    ```
  - **谁接 2（QA 通过后）**：前端线 E2 owner 先做 NEG 9 项 sema（type Foo/保留名/Array/true 声明），再接 PKG-01；G9 已由 `c55dd8151645` 收口。
- **上一棒**（路径或 commit）：`handoff/GEN-01-sema.md`；基线 `94e24f4`
- **下一棒**（路径或 commit）：`handoff/ERR-01-B2.md`
- **last-green（前端线）**：`131c2449fb14`（main 合并后全仓 `go test ./... -count=1 -timeout 300s` exit 0）

## 接口合同

- sema 推断成功后写回 `Call.TypeArgs`；codegen 以 `callName(name, TypeArgs)` 生成实例名 `xn_<fn>_<编码>`。
- 诊断码：`GEN-101` 显式实参、`GEN-102` 推断冲突/未绑定、`GEN-103` 重载歧义/零候选、`GEN-104` 作用域/new T/无限展开。
- 实例展开：`generics.go` 按 `Call.TypeArgs` 注册并展开，深度上限 64；`types.go` 的 `exprType` 走 `substitute`。
