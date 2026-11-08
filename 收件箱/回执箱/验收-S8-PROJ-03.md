# 验收：S8-PROJ-03（依赖与仲裁）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（S8-03b 依赖图/同深度仲裁/冲突路径/锁集成后复签）
> **复验点**：main `d70ff7a`（含 E6 `755e12b` S8-03b；cli 重复定义 P0 已恢复）
> **时间**：2026-11-08
> **证据**：`evidence/S8-QA/PROJ-03b/`
> **依据**：S8 §4、PROJ-03；S8-03b 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 传递依赖图 | **PASS**：BFS 图；锁含传递依赖 |
| 最近优先仲裁 | **PASS**：`g:x=1.0.0`（根直接依赖） |
| 同深度多版本冲突 | **PASS**：`XPD-403` |
| 冲突路径输出 | **PASS**：`g:a@1.0.0` / `g:b@1.0.0` / `g:x@2.0.0` / `g:x@3.0.0` |
| `dependencyManagement` 恒优先 | **PASS**：`g:x=5.0.0` |
| scope 传播（test/provided 不传递） | **PASS** |
| exclusions 剪枝 | **PASS** |
| 依赖环 | **PASS**：`XPD-409` |
| 锁覆盖传递闭包 + 404/405/406 | **PASS** |
| `xnull lock` / `--update-lock` | **PASS**：`TestLockCommand`（cli 包已恢复编译） |

**判定：PASS。** 上一轮“无依赖图/无同深度仲裁”的缺口已由 `755e12b` 关闭；锁集成 CLI 编译 P0 已修复。

---

## 二、实测

```text
$ go test ./internal/manifest -run 'TestGraph|TestLock' -count=1 -v
PASS TestGraphTransitive
PASS TestGraphArbitration（最近优先 / 同深度冲突 XPD-403）
PASS TestGraphConflictPaths（四段路径）
PASS TestGraphRules（管理版本优先 / test scope 不传递 / exclusions / 环 XPD-409）
PASS TestLockGenerateAndValidate / TestLockSortOrder / TestLockBytesStableFromGraph

$ go test ./internal/cli -run TestLockCommand -count=1 -v
PASS（缺锁失败、--update-lock 生成、校验通过、清单变更 XPD-404）
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| 仓库元数据 | 仅本地 `XNULL_REPO` `g/a/v/xnull.project`；远程/内嵌元数据未接 |
| `optional` | 已解析但未参与裁决 |
| 插件入锁 | `kind=plugin` 未生成（S8-05） |
| `xnull build` 清单模式 | 未接（S8-04） |

---

## 四、证据

- `evidence/S8-QA/PROJ-03b/matrix.tsv`
- `graph-tests.log`（TestGraph* / TestLock*）
- `lock-cli.log`（TestLockCommand）
- `source-contract.txt`
- `impl/internal/manifest/graph.go`、`impl/internal/cli/lock.go`
- `收件箱/回执箱/回执-S8-03b.md`
