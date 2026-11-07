# 接力棒：NEG-01

- **卡片ID**：NEG-01（负例矩阵 60 项）＋ interp 域剩余项（TUPLE-01 QA F1/F2）
- **输入**（上游产物/条款/接口）：S1 §0.6/§1.3/§3.2/§10.4/§2.11/§6.1、§2.8/§2.11 相等语义；用例源 `wt/c3-rd3/impl/Tests/neg_test.go`；被测基线 main `f548b54`。
- **输出文件**（精确路径）：`impl/internal/interp/interp.go`（`valuesEqual`/`identical`/字符串字面量驻留）、`impl/internal/interp/interp_test.go`（`TestTupleReferenceElementEquality`、`TestTupleStringIdentity`）、`evidence/NEG-INTERP/`；本文件 `handoff/NEG.md`。
- **commit**：`e91e33c`（main；`pod/e3-interp@a0e4038` 已合并，含 TUPLE F1/F2 修复 `f53f6fb`）。
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
  - NEG 60 项已 **60/60 PASS**（commit `3749bd390b14`，merge main `20f101d` 后 HEAD `b17e5cc`）；类型别名/Array/true/6 保留名全部拒绝。
  - interp 域剩余项已修：TUPLE-01 QA F1（引用元素 `==` 按对象身份）、F2（String `===` 按对象身份 + 字面量驻留）；QA interp 用例 8/8 PASS（原 5/8）。
  - PKG-01 解释路径：`examples/multi/main.x` 双路径逐字节一致；PKG 的 F1/F2/F3 均为 sema 别名/XDK 诊断，不涉 interp。
  - TUPLE 编译路径仍无 codegen 实现（验收已登记），本次只核解释路径。
  - main 合并已完成：`e91e33c`（外部 `cli.go` 冲突已由后续提交解除，合并无冲突）。
- **下一步**（谁接、做什么）：E2 接 PKG F1/F2/F3（同包不同符号别名、`xdk.net.http`、别名与裸导入同名）；QA1/E3 复跑 NEG 60/60。验证命令见 `handoff/PKG-01.md`。
- **上一棒**（路径或 commit）：`handoff/NEG.md` 上一版（main `1b9f096`，NEG 51/60）。
- **下一棒**（路径或 commit）：E2 修 sema 9 项（清单见 `handoff/PKG-01.md`）。
