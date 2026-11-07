# 请求：GEN-01 独立验收（E2 → QA1）

- 发起：E2（前端线 owner）
- 时间：2026-11-07
- 关联：S1/M1 GEN-01；ADR-001/002 试行
- 性质：请求 QA1 独立验收；执行侧自检不替代签署

## 结论送审

- 检查表：**26/26**（`TestGEN01` 25 子项 + `TestGEN01CrossFile` 1 项），0 FAIL / 0 SKIP。
- 代码提交：`20e3d838ea45`；集成合入 main 后 HEAD：`131c2449fb14`。
- 证据：`evidence/M1-GEN-01/e2-final/`（acceptance、command、三份原始日志 + 合并后全量日志）。
- 接力棒：`handoff/GEN-01.md`。

## 独立复跑命令

```bash
cd impl
go test ./internal/codegen/ -run 'TestGEN01' -v -count=1
go test ./internal/sema/  -run 'TestGEN01' -v -count=1
go test ./... -count=1 -timeout 300s
```

期望：前两条 exit 0；GEN 25 子项 + CrossFile 全 PASS；全仓 exit 0。

## 独立用例要求

1. QA 必须另写独立用例，**不得复用** `gen01_acceptance_test.go` 的期望值与源码。
2. 26 项清单：G1a/G1b/G2a/G2b/G2c/G2d/G3/G4/G5a/G5b/G5c/G6a/G6b/G7/G8（台账 8 要点拆 15 用例）+ G9–G19（S1 §8 补充 11 项，G16 以跨文件用例计）。
3. 重点独立覆盖：显式实参、局部推断、嵌套 `List<T>` 合一、冲突绑定、未绑定、普通/泛型重载、`Result<T,String>`、跨文件模板可见。

## 已知边界（请一并判定）

- G7：当前以“直接自递归 → `GEN-104 展开`”验收；嵌套 `grow<List<T>>` 受 xfront `>>` 拆分（EXP-008）限制。
- G12：以“泛型函数作为值 → 解析拒绝”验收；诊断为 SYN-102 级联，质量待 xfront 整改。
- codegen 实例展开深度上限 `maxInstDepth=64`；跨包泛型仅验证 `LoadUnits` 合并后可见。

## QA 签署后

- 由 SSOT 将 `status.tsv` GEN-01 翻 PASS（M1 7/14）。
- E2 接 `handoff/ERR-01-B2.md`（诊断位置）。
