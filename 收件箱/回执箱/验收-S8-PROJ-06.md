# 验收：S8-PROJ-06（插件）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（插件元数据/声明一致性/沙箱/禁网/非零退出通过；构建期接线为 S8-04 边界）
> **复验点**：main `468541b`（含 S8-05 `e991463` 插件）
> **时间**：2026-11-08
> **证据**：`evidence/S8-QA/PROJ-06/`
> **依据**：S8 §5.5、PROJ-06；S8-05 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `.xplugin` 缺失/字段不符 | **PASS**：`XPD-504` |
| 版本精确；phase 合法 | **PASS**：`XPD-501` |
| 未声明 goal / phase 不符 | **PASS**：`XPD-501` |
| `configuration` 键未声明 | **PASS**：`XPD-501` |
| 坐标/版本/工具链主版本一致性 | **PASS**：`XPD-504` |
| 插件写 `target/` 内允许 | **PASS** |
| 插件写 `target/` 外拒绝 | **PASS**：`XPD-502` |
| 禁网 / 无沙箱拒绝执行 | **PASS**：`XPD-505`；`sandbox-exec (deny network*)` |
| 非零退出即失败 | **PASS**：`XPD-503` |
| 插件依赖不进编译类路径 | **PASS（结构隔离）**：独立 `internal/plugin`，未进入 codegen 类路径 |

**判定：PASS。** 插件声明、执行策略与沙箱合同成立；构建期阶段接线属 S8-04。

---

## 二、实测

```text
$ go test ./internal/plugin -count=1 -v
PASS TestLoadMetadata（缺字段/goal 缺 phase/phase 非法/configKeys 非列表/缺失文件）
PASS TestValidateDeclaration（版本/phase/goal/configKeys/坐标/版本/toolchain 8 例）
PASS TestRunPolicy（target 内写/target 外写 XPD-502/exit 3 XPD-503/无沙箱 XPD-505）
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| 构建期插件阶段 | 待 S8-04 接入；本卡为插件包级合同 |
| 网络拒绝 | `sandbox-exec` profile `(deny network*)`；不可用时 `XPD-505` 拒绝执行 |
| 插件依赖类路径 | 插件包独立，编译类路径未加入 |

---

## 四、证据

- `evidence/S8-QA/PROJ-06/matrix.tsv`
- `plugin-tests.log`
- `source-contract.txt`
- `impl/internal/plugin/plugin.go`
- `收件箱/回执箱/回执-S8-05.md`
