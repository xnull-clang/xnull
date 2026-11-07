# 验收：S8-PROJ-02（继承）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `d779380`（含 S8-02 `01c5b2e`）
> **时间**：2026-11-08
> **证据**：`evidence/S8-QA/PROJ-02/`
> **依据**：S8 §3.3、PROJ-02；S8-02 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 单父展开 + properties 子覆盖父 | **PASS** |
| 深度 > 8 失败 | **PASS**：`XPD-303` |
| 环 / self-parent 失败 | **PASS**：`XPD-304` |
| parent 缺失 / 非 pom | **PASS**：`XPD-305/306` |
| 坐标不从父继承 | **PASS**：子 `artifactId=child` |
| properties / dependencies / configuration 合并 | **PASS** |
| 变量替换（单次/内置/未解析） | **PASS**：`XPD-307/308` |

**判定：PASS。** 继承链限制、坐标自声明与合并规则全部成立。

---

## 二、实测

```text
$ go test ./internal/manifest -count=1 -v
PASS TestParentChainRules
  单父合并 / 缺坐标失败 / 深度超限 / 环与 self-parent / parent 缺失/非 pom
PASS TestPropertySubstitution
PASS TestProfiles
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| parent 定位 | 仅 `relativePath`；本地/远程仓库定位未接 |
| 合并范围 | properties/dependencies/build/configuration；dependencyManagement/repositories/plugins 未合并 |
| `xnull build` 清单模式 | 未接（S8-04） |

---

## 四、证据

- `evidence/S8-QA/PROJ-02/matrix.tsv`
- `manifest.log`
- `impl/internal/manifest/manifest_test.go`
- `收件箱/回执箱/回执-S8-02.md`
