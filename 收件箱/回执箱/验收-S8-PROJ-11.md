# 验收：S8-PROJ-11（资源）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（清单侧资源收割/glob/冲突/依赖合并/pom/symlink 通过；build 接线为 S8-04 边界）
> **复验点**：main `468541b`（含 S8-08 `2431f8e` 资源收割器）
> **时间**：2026-11-08
> **证据**：`evidence/S8-QA/PROJ-11/`
> **依据**：S8 §5.6、PROJ-11；S8-08 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 缺省资源根/显式根收录 | **PASS**：`Collect` |
| includes/excludes 优先级与 glob | **PASS**：`TestCollectGlobAndPrefix`、`TestGlobSemantics` |
| 制品内 `resources/<相对路径>` 前缀 | **PASS** |
| 多来源同路径冲突点名双来源 | **PASS**：`XPD-803` |
| 依赖库资源合并进 app；冲突失败 | **PASS**：`TestMergeDependency` |
| starter 资源不合并给使用者 | **PASS** |
| `pom` 出现资源根失败 | **PASS**：`XPD-804` |
| symlink 跟随；断链失败 | **PASS**：`XPD-805` |
| 测试资源隔离（main/test phase） | **PASS**：`CollectForPhase` |
| 非法资源根/非法 glob | **PASS**：`XPD-801/802` |

**判定：PASS。** 清单侧收割器覆盖 glob、前缀、冲突、依赖合并、starter/pom 与 symlink；`build` 接线属 S8-04。

---

## 二、实测

```text
$ go test ./internal/resman -count=1 -v
PASS TestCollectGlobAndPrefix
PASS TestGlobSemantics（10 例）
PASS TestConflictNamesBothSources（XPD-803，双来源）
PASS TestMergeDependency（library 合并 / starter 不合并 / 冲突）
PASS TestSymlinks（跟随 / 断链 XPD-805）
PASS TestPhaseAndPackaging（main/test 隔离 / pom XPD-804）
PASS TestInvalidRootAndGlob（XPD-801/802）
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| build 清单模式接线 | 待 S8-04；本卡为 resman 收割器 |
| 缺省 `src/main/resources` 自动发现 | 由 S8-04 生命周期接 |
| `.x` 数据打包 / 无过滤字节 | 收割器按字节复制；专项断言待 build 接线 |
| 资源配置子目录/模块根拒绝 | schema 层已有位置规则，运行期待接线 |

---

## 四、证据

- `evidence/S8-QA/PROJ-11/matrix.tsv`
- `resman-tests.log`
- `source-contract.txt`
- `impl/internal/resman/resman.go`
- `收件箱/回执箱/回执-S8-08.md`
