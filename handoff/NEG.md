# 接力棒：NEG-01

- **卡片ID**：NEG-01（负例矩阵 60 项）＋ interp 域剩余项（TUPLE-01 QA F1/F2）
- **输入**（上游产物/条款/接口）：S1 §0.6/§1.3/§3.2/§10.4/§2.11/§6.1、§2.8/§2.11 相等语义；用例源 `wt/c3-rd3/impl/Tests/neg_test.go`；被测基线 main `f548b54`。
- **输出文件**（精确路径）：`impl/internal/interp/interp.go`（`valuesEqual`/`identical`/字符串字面量驻留）、`impl/internal/interp/interp_test.go`（`TestTupleReferenceElementEquality`、`TestTupleStringIdentity`）、`evidence/NEG-INTERP/`；本文件 `handoff/NEG.md`。
- **commit**：`f53f6fb`（`pod/e3-interp`，未 push；main 合并被外部在途冲突阻塞，见下）。
- **验证命令**（可复制）：
  ```bash
  mkdir -p impl/Tests && cp wt/c3-rd3/impl/Tests/neg_test.go impl/Tests/
  cd impl
  go test ./Tests -run '^TestDiagMatrixS1$' -count=1 -v                        # 51 PASS / 9 FAIL
  go test ./Tests -run '^TestDiagMatrixS1Alternatives$' -count=1 -v             # 9/9 PASS
  go test ./internal/interp -run 'TestTupleReferenceElementEquality|TestTupleStringIdentity|TestResultMemberMisusePanics' -count=1 -v
  go test ./internal/interp/... -count=1                                        # ok
  /tmp/xnull-e3 run --interp examples/multi/main.x > /tmp/i.out
  /tmp/xnull-e3 run examples/multi/main.x > /tmp/c.out && diff /tmp/i.out /tmp/c.out
  ```
- **已知缺口/风险**：
  - NEG 60 项 **51 PASS / 9 FAIL**，**interp 失败项 0**；9 项全在 sema（前端线 E2）：类型别名 `neg-0.6-41`、保留名 `neg-1.3-01..06`、`Array` 类型名 `neg-1.3-08`、`true` 声明名 `neg-1.3-09`。
  - interp 域剩余项已修：TUPLE-01 QA F1（引用元素 `==` 按对象身份）、F2（String `===` 按对象身份 + 字面量驻留）；QA interp 用例 8/8 PASS（原 5/8）。
  - PKG-01 解释路径：`examples/multi/main.x` 双路径逐字节一致；PKG 的 F1/F2/F3 均为 sema 别名/XDK 诊断，不涉 interp。
  - TUPLE 编译路径仍无 codegen 实现（验收已登记），本次只核解释路径。
  - **main 合并阻塞**：main 工作区有外部在途冲突 `UU impl/internal/cli/cli.go`（IDE-SOURCE），本卡未触碰；需 owner 先解冲突再合 `f53f6fb`。
- **下一步**（谁接、做什么）：①owner 解 main 的 `cli.go` 冲突 → 合 `pod/e3-interp@f53f6fb`；②E2 修 9 项 sema → NEG 60/60；③QA 复验 TUPLE interp 8/8。
- **上一棒**（路径或 commit）：`handoff/NEG.md` 上一版（main `1b9f096`，NEG 51/60）。
- **下一棒**（路径或 commit）：E2（sema 9 项）＋ owner 集成 `f53f6fb`。
