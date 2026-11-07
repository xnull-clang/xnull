# 接力棒：NEG-01

- **卡片ID**：NEG-01（负例矩阵，60 项）
- **输入**（上游产物/条款/接口）：S1 §0.6/§1.3/§3.2/§10.4/§2.11/§6.1；用例源 `wt/c3-rd3/impl/Tests/neg_test.go`（c3-rd3 `ff99035`）；被测 main `8beda11`（含 ERR-01 闭包 try 修复、sema TYPE-01/ERR 修复、`d1d3e11`）。
- **输出文件**（精确路径）：本文件 `handoff/NEG.md`；用例仍只在 `wt/c3-rd3/impl/Tests/neg_test.go`（未复制进 main，避免无主测试包）。
- **commit**：`8beda11`（本轮输入基线；本接力棒提交见 `git log -- handoff/NEG.md`）。
- **验证命令**（可复制）：
  ```bash
  mkdir -p impl/Tests && cp wt/c3-rd3/impl/Tests/neg_test.go impl/Tests/
  cd impl
  go test ./Tests -run '^TestDiagMatrixS1$' -count=1 -v            # 51 PASS / 9 FAIL
  go test ./Tests -run '^TestDiagMatrixS1Alternatives$' -count=1 -v # 9/9 PASS
  go test ./internal/interp -run 'TestResultMemberMisusePanics' -count=1 -v # 2/2 PASS
  ```
- **已知缺口/风险**：60 项 **51 PASS / 9 FAIL**。9 项全部在 sema（前端线 E2），interp 项已闭环：
  - `neg-0.6-41` 类型别名 `type Foo = Int` 未拒绝；
  - `neg-1.3-01..06` 保留名 `async/await/yield/unsafe/extern/macro` 可作标识符；
  - `neg-1.3-08` `Array` 可作类型名；
  - `neg-1.3-09` `true` 可作声明名且声明被静默丢弃。
  - interp：`Err.value()` / `Ok.error()` 运行期 fatal（`TestResultMemberMisusePanics`，2/2 PASS，commit `a5fb086` 已合 main）；`neg-3.2-02`（包别名）已由 xfront 修复转绿。
- **下一步**（谁接、做什么）：E2（前端线）修上述 9 项 sema 校验并补诊断位置；复跑 `TestDiagMatrixS1` 至 **60/60**。E3 不再有 NEG interp 待办。
- **上一棒**（路径或 commit）：`wt/c3-rd3` 回执 `收件箱/回执箱/CEO3/回执-M1-NEG-01.md`（`ff99035`，main@7df123d 时 50/60）。
- **下一棒**（路径或 commit）：E2 修 sema 后更新本文件，目标 60/60；用例与期望不改。
