# 接力棒：GEN-01 sema

- **卡片ID**：GEN-01 sema（前端线 P0，E2 独占）
- **输入**（上游产物/条款/接口）：
  - 台账 `XNull一致性用例台账-v1.0.0.md:27` GEN-01 验收要点
  - `XNull解决方案-第1部分-基础语法-v3.3.0.md` §8.1–§8.4
  - main 已合入的 `impl/internal/sema/generic.go`、`gen01_test.go`
  - 历史检查表与红源：`evidence/M1-GEN-01-sema/checklist-source.md`、`before/`
- **输出文件**（精确路径）：
  - `impl/internal/sema/generic.go`
  - `impl/internal/sema/gen01_test.go`
  - `impl/internal/sema/gen01_extra_test.go`（G10/G12/G17）
  - `impl/internal/sema/gen01_crossfile_test.go`（G16，external test package）
- **commit**：`337f6070c532`（卡片提交）；集成合入后 HEAD `5989ef2`
- **验证命令**（可复制）：
  ```bash
  cd impl
  go test ./internal/sema/ -run 'TestGEN01' -v -count=1
  go test ./internal/sema/ -count=1
  go test ./... -count=1 -timeout 300s
  ```
  结果：GEN-01 sema 全部 PASS；全仓 exit 0。
- **已知缺口/风险**：
  - GEN-01 台账 26 项均已有 sema 测试映射；G12 以“解析拒绝”验证，诊断质量仍差（SYN-102 级联），属 xfront。
  - G16 仅验证 `codegen.LoadUnits` 合并后 sema 可见；codegen 泛型实例发射/解释器泛型执行未在本卡闭环，GEN-01 锚点状态仍为“未实现”。
  - `status.tsv` 未手改；需 QA/SSOT 按端到端结果更新。
- **下一步**（谁接、做什么）：
  - E2 owner 集成下一卡：`ERR-01 B2 诊断位置`（`LocalDeclStmt` 行列非零 + 全诊断码守门测试）。
  - GEN-01 端到端（codegen/interp）转 E4/E3 线；E2 只维护 sema 合同与回归。
- **上一棒**（路径或 commit）：`5989ef2`（main merge，含 ADR-003）；卡片红源见 `evidence/M1-GEN-01-sema/`
- **下一棒**（路径或 commit）：`handoff/ERR-01-B2.md`（待建）
- **last-green（前端线）**：`5989ef2`（全仓 `go test ./... -count=1 -timeout 300s` exit 0）

## 接口合同

- sema 推断成功后写回 `Call.TypeArgs`（`TestGEN01WritesBackTypeArgs`），codegen 单态化消费该字段。
- 诊断码：`GEN-101`（显式实参）、`GEN-102`（推断冲突/未绑定）、`GEN-103`（重载歧义/零候选）、`GEN-104`（作用域/new T/无限展开）。
