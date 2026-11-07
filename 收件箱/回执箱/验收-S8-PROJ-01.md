# 验收：S8-PROJ-01（工程清单骨架与坐标）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（S8-01b schema 校验 `97a47f7` 后复签）
> **复验点**：main `78475a7`（含 E6 `97a47f7` manifest schema validation）
> **时间**：2026-11-08
> **证据**：`evidence/S8-QA/PROJ-01b/`
> **依据**：S8 §2/§3/§9、PROJ-01；S8-01b 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 骨架/坐标：groupId/artifactId/version/packaging | **PASS**：缺字段 → XPD-301；manifest 逐字段校验 |
| 未知段落/字段/顶层块 | **PASS**：XPD-201 |
| 单次段落/字段/project 重复 | **PASS**：XPD-202（三例） |
| 容器段落只含规定条目 | **PASS**：XPD-203（非法条目/非法块） |
| 依赖坐标重复 | **PASS**：XPD-302 |
| 诊断带 xpd 位置 | **PASS**：`xnull.project:6` |
| XPD-2xx/3xx 码位 | **PASS**：201/202/203、301/302（+ manifest 303–309） |

**判定：PASS。** 上一轮“仅词法/文法、无 `ValidateProject`”的缺口已由 `validate.go` 接入 `Load` 关闭；schema 11 子用例与位置断言全过。

---

## 二、实测

```text
$ go test ./internal/manifest -count=1 -v
PASS TestSchemaValidation
  PASS 未知段落 / 未知字段 / 未知顶层块
  PASS 段落重复 / 字段重复 / project 重复
  PASS 容器非法条目 / 容器含非法块
  PASS 依赖坐标重复 / 缺坐标 / packaging 非法值（占位合法）
PASS TestSchemaPositions
```

诊断示例：未知字段 `xnull.project:6`，码 `XPD-201`；缺 version `XPD-301`；依赖同坐标 `XPD-302`。

---

## 三、边界

| 项 | 说明 |
|---|---|
| packaging 枚举取值 | S8-01b 回执列为未测风险；本卡只验四字段结构/缺失 |
| 依赖坐标语法 | 归 S8-03（依赖管理/锁） |
| `xnull build` 清单模式 | 仍未接（S8-04） |

---

## 四、证据

- `evidence/S8-QA/PROJ-01b/matrix.tsv`
- `manifest-tests.log`（TestSchemaValidation / TestSchemaPositions）
- `source-contract.txt`（schema 用例）
- `impl/internal/manifest/validate.go`
- `收件箱/回执箱/回执-S8-01b.md`
