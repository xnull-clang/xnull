# 接力棒：PKG-01（含 TUPLE-01 interp 复核）

- **卡片ID**：PKG-01（包导入/多文件）+ TUPLE-01 interp F1/F2 复核
- **输入**（上游产物/条款/接口）：S1 §3.2（包/导入）、§2.8/§2.11（元组相等/同一性）；验收依据 `收件箱/回执箱/CEO1/验收-M1-PKG-01.md`、`收件箱/回执箱/CEO3/验收-M1-TUPLE-01.md`；基线 main `d349f6a`，集成后 main `e91e33c`。
- **输出文件**（精确路径）：
  - `impl/internal/interp/interp.go`：`valuesEqual` 引用类型按对象身份 + String 字面量驻留；`identical` 的 String `===` 按对象身份（commit `f53f6fb`，已合 main `e91e33c`）。
  - `impl/internal/interp/interp_test.go`：`TestTupleReferenceElementEquality`、`TestTupleStringIdentity`。
  - 证据 `evidence/NEG-INTERP/`（tuple QA、PKG 双路径、NEG 60 项、全量测试）。
  - 本文件 `handoff/PKG-01.md`。
- **commit**：`e91e33c`（main；`pod/e3-interp@a0e4038` 的 merge）。
- **验证命令**（可复制）：
  ```bash
  cd impl
  # TUPLE interp 独立 QA（8 项）
  cp ../evidence/M1-TUPLE-01-qa/qa-tests/qa-interp_tuple_test.go internal/interp/qa_tuple_accept_test.go
  go test ./internal/interp -run 'TestQATuple' -count=1 -v   # 8/8 PASS
  rm internal/interp/qa_tuple_accept_test.go
  # PKG 解释路径（多文件）
  go build -o /tmp/xnull-e3 ./cmd/xnull
  /tmp/xnull-e3 run --interp ../examples/multi/main.x > /tmp/i.out
  /tmp/xnull-e3 run          ../examples/multi/main.x > /tmp/c.out
  diff /tmp/i.out /tmp/c.out                                  # 逐字节一致
  # NEG 60 项
  mkdir -p Tests && cp ../../wt/c3-rd3/impl/Tests/neg_test.go Tests/
  go test ./Tests -run '^TestDiagMatrixS1$' -count=1 -v       # 51 PASS / 9 FAIL（全 sema）
  rm -rf Tests
  ```
- **已知缺口/风险**：
  - **PKG-01 sema 仍有 3 项**（非 interp）：F1 同包不同符号共用别名未报 `RES-103`；F2 `import xdk.net.http` 被误拒；F3 别名与裸导入同名未报 `RES-103`。位置：`impl/internal/sema/xdk.go:168/:216/:123`。归 E2。
  - **TUPLE 编译路径**：codegen 无元组实现，本次只核解释路径；TUPLE F3（可空元组 `?.`）仍属 xfront，F4 字面量表示性挂 M2-C。
  - PKG 多文件双路径本次 MATCH；不替代 PKG sema 的 49 项独立验收。
- **NEG 9 项 sema 清单（交 E2）**：NEG 现状 **51/60**，interp 失败项 **0**。
  | 用例 | 缺口 | 位置 |
  |---|---|---|
  | `neg-0.6-41` | `type Foo = Int` 类型别名未拒绝 | sema 类型名可解析性 |
  | `neg-1.3-01..06` | 保留名 `async/await/yield/unsafe/extern/macro` 可作标识符 | `xfront.Reserved` 无消费者 |
  | `neg-1.3-08` | `Array` 可作类型名 | `sema/typedecl.go` 黑名单 |
  | `neg-1.3-09` | `true` 可作声明名且声明被丢弃 | `sema/sema.go:149-157` |
- **下一步**（谁接、做什么）：E2 修上表 9 项 + PKG F1/F2/F3；复跑 `TestDiagMatrixS1` 至 60/60、PKG 49 子项至 49/49；QA 复验 TUPLE interp 8/8 与 multi 双路径。
- **上一棒**（路径或 commit）：`handoff/NEG.md`（`a0e4038`，NEG 51/60）。
- **下一棒**（路径或 commit）：`handoff/PKG-01.md` 本文件，`main@e91e33c`。
