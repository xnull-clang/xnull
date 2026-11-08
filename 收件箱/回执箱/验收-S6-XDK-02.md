# 验收：S6-XDK-02（合同原则）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `278c772`（含 XDK-02 静态核验 `b5737a8`）
> **时间**：2026-11-08
> **证据**：`evidence/S6-QA/XDK-02/`
> **依据**：S6 §1.4/§2；XDK-02；`收件箱/门/S6验收计划-E2.md`
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 合同原则 | 结果 |
|---|---|
| 可失败操作返回 `Result` | **PASS**：`TestS601XDK02Clause1Result` |
| 默认异步/可阻塞 API 首参 `Context` | **PASS**：`TestS601XDK02Clause3ContextFirst` |
| 依赖方向/依赖环 | **PASS**：`TestXDKContractsDependencyViolation`、`Cycle` |
| 命名/稳定性矩阵 | **PASS**：`TestXDKContractsNaming`、`StabilityMismatch` |
| 无隐藏全局可变状态 | **PASS**：`TestXDKContractsImplicitGlobal` |
| 资源 close 合同 | **PASS**：`TestXDKContractsResourceClose` |
| 真仓库 8 单元核验 | **PASS**：`TestXDKContractsRepo` |
| 阻塞分类清单 | **PASS**：`TestBlockingClassificationDocInSync` |

**判定：PASS。** `b5737a8` 的静态核验与 sema 条款覆盖七条原则；固定夹具红/绿与真仓库审计均通过。

---

## 二、实测

```text
$ go test ./internal/codegen -run 'TestXDKContracts' -count=1
PASS（FixturePass / DependencyViolation / Cycle / Naming /
      StabilityMismatch / ImplicitGlobal / ResourceClose / Repo）

$ go test ./internal/sema -run 'TestS601XDK02' -count=1
PASS（Clause1Result / Clause3ContextFirst）

$ go test ./internal/codegen/ffi -run TestBlockingClassificationDocInSync
PASS
```

---

## 三、证据

- `evidence/S6-QA/XDK-02/matrix.tsv`
- `contracts.log`、`sema.log`、`blocking.log`
- `收件箱/回执箱/回执-S6-XDK02-E2.md` / `impl/internal/codegen/xdk_contract_test.go`
