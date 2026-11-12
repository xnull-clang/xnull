# 验收：S8-CLI-TREE-WHY（`xnull tree` / `xnull why`）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（依赖树与引入路径正确；`why` 的 management 路径标签有 P2 显示问题）
> **复验点**：main `d963b02`（含 S8-17 `1cf40e7`）
> **时间**：2026-11-08
> **证据**：`evidence/S8-17-E2E/`、`tests/s8/s817/`、`matrix-TREE-WHY.tsv`
> **依据**：S8 §4.2、S8-17 回执
> **确认方式**：读取 `.git/refs/heads/main`；执行 `xnull tree/why`；未做 git 操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `tree` 根 GAV + 直接依赖 | **PASS**：`g:app@1.0.0`、`g:a@1.0.0`、`g:c@1.0.0` |
| `tree` 传递依赖缩进 | **PASS**：`g:x@1.0.0` 位于 `g:c@1.0.0` 下，两层缩进 |
| `tree` 同级排序 | **PASS**：`a` 在 `c` 前 |
| `tree` 同深度冲突 | **PASS**：`XPD-403`，exit 1（不静默取第一个） |
| `tree` 无传递依赖 | **PASS**：仅根 + 一个直接子 |
| `why` 传递依赖 | **PASS**：版本/路径 `g:c@1.0.0 -> g:x@1.0.0`/来源“最近优先”/深度 2 |
| `why` 直接依赖 | **PASS**：来源“直接依赖”，深度 1 |
| `why` management 固定 | **PASS**：版本 `2.0.0`，来源“dependencyManagement 固定”（路径标签见 P2） |
| `why` 未解析坐标 | **PASS**：exit 2 |
| `why` 缺坐标 | **PASS**：exit 2 |

**判定：PASS。** 树形结构、仲裁结果与解释路径可用；冲突按 S8 §4.2 直接失败。

---

## 二、实测

```text
$ XNULL_REPO=tests/s8/s817/repo xnull tree
g:app@1.0.0
  g:a@1.0.0
  g:c@1.0.0
    g:x@1.0.0

$ xnull why g:x
坐标：g:x
版本：1.0.0
路径：g:c@1.0.0 -> g:x@1.0.0
来源：最近优先（路径最短）
深度：2

$ 直接依赖 → 路径 g:x@1.0.0；来源 直接依赖；深度 1
$ management 钉 2.0.0 → 版本 2.0.0；来源 dependencyManagement 固定
$ tree 冲突 → XPD-403，exit 1
$ why g:nope → exit 2；why 无参数 → exit 2
```

---

## 三、缺陷与边界

| 项 | 说明 |
|---|---|
| P2：`why` management 路径标签 | 版本为 `2.0.0`，但“路径”节点仍显示声明候选 `g:x@1.0.0`；建议路径末节点使用仲裁后版本，或注明“声明候选” |
| 代表路径 | 同一坐标只展示一条仲裁代表路径；被裁剪候选不展开（回执已披露） |
| 未标注 scope/optional | tree/why 不输出 scope；test/provided 不传递的语义不可见 |
| 冲突策略 | 同深度冲突直接报错，不输出部分树 |
| 外部依赖 | 元数据来自 `XNULL_REPO`；无元数据时视为叶子（不展开子依赖） |

---

## 四、证据

- `evidence/S8-17-E2E/tree.log`、`tree-direct.log`、`tree-conflict.log`
- `evidence/S8-17-E2E/why-transitive.log`、`why-direct.log`、`why-managed.log`
- `evidence/S8-17-E2E/why-unknown.log`、`why-noarg.log`
- `evidence/S8-17-E2E/matrix-TREE-WHY.tsv`
- 夹具：`tests/s8/s817/{tree,direct,managed,conflict}/`、`tests/s8/s817/repo/`

---

## 五、二次执行记录（2026-11-08 19:31，同 main `d963b02`）

- 重建二进制 `/tmp/xnull-s817b` 后重跑：tree 树形/冲突负例、why 四类来源与两个错误路径均与首轮一致。
- 结论不变：tree PASS、why PASS（P2 路径标签备注保留）。
- 证据：`evidence/S8-17-E2E/{tree*,why-*}.log`（已按本轮更新）。

## 六、三次抽检（main `6307f7e`）

- `tree` 输出 `g:app@1.0.0 → a/c → x`；`why g:x` 路径 `g:c@1.0.0 -> g:x@1.0.0`、来源最近优先、深度 2。PASS 结论不变。
- 证据：`evidence/S8-17-E2E/LATEST-tree.log`、`LATEST-why.log`。
