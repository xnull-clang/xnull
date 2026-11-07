# 验收：M1-PKG-01（包与导入）

> **验收人**：QA1（独立质量线）
> **结论：PASS 49/49（sema 独立用例面）**
> **复验点**：main `1ca2153`（含合并 `3174618`：PKG F1 `d3053f1`、F2 `b7e2d0e`、F3 `b4ecc70`）
> **用例**：`evidence/M1-PKG-01-qa/qa2_independent_test.go`（QA1 自写，49 子项）
> **时间**：2026-11-07

---

## 一、结论

| 项 | 结果 |
|---|---|
| 独立子用例 | 49 |
| PASS | **49** |
| FAIL | **0** |
| 原 F1（同包不同符号同别名） | **PASS**（`RES-103`） |
| 原 F2（合法多级 XDK 包） | **PASS**（接受 `import xdk.net.http`） |
| 原 F3（别名与裸导入同名） | **PASS**（`RES-103`） |

> 本 PASS 的验收面是 sema 的 `AnalyzeWithDeps`。CLI 多文件路径的补充观察见 §五，
> **不计入 49 项**，原验收单“未跑清单”第 3 条亦已声明 CLI 未接导入诊断。

---

## 二、逐项结果（49）

### 2.1 `TestQA2SymbolImport`（7）

| # | 子项 | 判据 | 结果 |
|---:|---|---|---|
| 1 | single-symbol-visible | 符号导入仅暴露该符号 | PASS |
| 2 | sibling-symbol-hidden | 同包兄弟符号不可见 | PASS |
| 3 | symbol-missing | 符号不存在报 RES-106 | PASS |
| 4 | private-symbol | 私有符号不可导入 | PASS |
| 5 | protected-symbol | 受保护符号导入规则 | PASS |
| 6 | class-symbol | 类符号可导入 | PASS |
| 7 | private-class-symbol | 私有类不可导入 | PASS |

### 2.2 `TestQA2Alias`（10）

| # | 子项 | 判据 | 结果 |
|---:|---|---|---|
| 8 | both-aliased | 双方别名互不冲突 | PASS |
| 9 | alias-replaces-original | 别名取代原名 | PASS |
| 10 | one-aliased-one-bare | 一方别名一方裸导入 | PASS |
| 11 | needless-alias-single | 单符号多余别名被拒 | PASS |
| 12 | package-alias-forbidden | 禁止包别名 | PASS |
| 13 | xdk-package-alias-forbidden | 禁止 XDK 包别名 | PASS |
| 14 | cross-source-alias-conflict | 跨来源同别名报 `RES-103` | PASS |
| 15 | **same-source-alias-conflict（F1）** | 同包不同符号同别名报 `RES-103` | **PASS** |
| 16 | alias-vs-top-level | 别名与顶层名冲突 | PASS |
| 17 | alias-vs-builtin | 别名与内建名冲突 | PASS |

### 2.3 `TestQA2Disambiguation`（7）

| # | 子项 | 判据 | 结果 |
|---:|---|---|---|
| 18 | two-bare-same-name | 两个裸导入同名报歧义 | PASS |
| 19 | duplicate-package-import | 重复包导入去重 | PASS |
| 20 | duplicate-symbol-import | 重复符号导入去重 | PASS |
| 21 | top-level-shadow | 顶层名遮蔽规则 | PASS |
| 22 | package-imports-share-symbol | 包导入共享符号 | PASS |
| 23 | three-sources-one-aliased | 三来源一别名 | PASS |
| 24 | alias-vs-bare-name | 别名与裸名消歧 | PASS |

### 2.4 `TestQA2Xdk`（11）

| # | 子项 | 判据 | 结果 |
|---:|---|---|---|
| 25 | use-without-import | 未导入使用 XDK 报错 | PASS |
| 26 | explicit-import | 显式导入可用 | PASS |
| 27 | user-import-does-not-mask | 用户导入不遮蔽 XDK | PASS |
| 28 | type-position-without-import | 类型位未导入报错 | PASS |
| 29 | type-position-with-import | 类型位已导入可用 | PASS |
| 30 | xdk-symbol-import | XDK 符号导入 | PASS |
| 31 | xdk-symbol-missing | 符号不存在报 `RES-106` | PASS |
| 32 | xdk-unknown-package | 未知 XDK 包报错 | PASS |
| 33 | xdk-root | `xdk` 根导入 | PASS |
| 34 | xdk-net-package | `xdk.net` 包导入 | PASS |
| 35 | **xdk-multilevel-package（F2）** | `import xdk.net.http` 接受 | **PASS** |

### 2.5 `TestQA2ImportCycle`（5）

| # | 子项 | 判据 | 结果 |
|---:|---|---|---|
| 36 | two-node | 两节点环报 `RES-108` | PASS |
| 37 | three-node | 三节点环报 `RES-108` | PASS |
| 38 | self-cycle | 自环报 `RES-108` | PASS |
| 39 | diamond-dag | 菱形 DAG 不误报环 | PASS |
| 40 | xdk-edge-not-cycle | XDK 边不参与环 | PASS |

### 2.6 `TestQA2TargetRules`（5）

| # | 子项 | 判据 | 结果 |
|---:|---|---|---|
| 41 | package-missing | 目标包缺失报错 | PASS |
| 42 | default-package-import | 默认包导入 | PASS |
| 43 | default-symbol-import | 默认包符号导入 | PASS |
| 44 | default-entry-imports-default-fragment | 入口导入默认片段 | PASS |
| 45 | private-use-after-package-import | 包导入后使用私有符号 | PASS |

### 2.7 `TestQA2SyntaxGuards`（3）

| # | 子项 | 判据 | 结果 |
|---:|---|---|---|
| 46 | xdk-prefix-package | `xdk` 前缀包语法守卫 | PASS |
| 47 | wildcard-import | 禁止通配符导入（§3.2） | PASS |
| 48 | import-after-declaration | import 必须在声明前 | PASS |

### 2.8 `TestQA2SameSourceAliasVsBare`（1）

| # | 子项 | 判据 | 结果 |
|---:|---|---|---|
| 49 | **alias-name-already-bound（F3）** | 别名与同包裸导入同名报 `RES-103` | **PASS** |

另外两个顶层测试 `TestQA2DiagnosticPosition`、`TestQA2Determinism` 亦 PASS（不占 49 子项名额）。

---

## 三、原失败项对照

| 项 | 原实测（main `d349f6a`） | 期望 | 现测（main `1ca2153`） | 判定 |
|---|---|---|---|---|
| F1 | `RES-102` 类型重复声明 | `RES-103` | `RES-103` | **PASS** |
| F2 | `RES-106` 无导出符号 `http` | 接受 | 接受（rc=0） | **PASS** |
| F3 | `RES-102` 类型重复声明 | `RES-103` | `RES-103` | **PASS** |

根因修复位置：`impl/internal/sema/xdk.go` 的来源标识由包路径改为完整导入来源；`xdk.<pkg>.<seg>` 按已知符号区分多级包导入。

---

## 四、已跑命令与结果

```bash
cd /Users/vjs/Desktop/XNull-Lang/wt/qa-1
bash difftest/anchors/run-pkg.sh --sha 1ca2153 --out evidence/QA1-verify-2026-11-07
```

原样输出：

```
Go 独立用例：PASS=49 / FAIL=0（exit 0）
```

历史对照：main `d349f6a` 为 46/49（F1/F2/F3 三项 FAIL）。

---

## 五、CLI 多文件补充观察（不计入 PKG-01 49 项）

用同一套语义构造跑 `xnull build`（`difftest/anchors/cases/pkg/`）：

| 用例 | 期望 | 现测 | 说明 |
|---|---|---|---|
| f1 | `RES-103` | `RES-102` 类型 `X`/`Y` 重复 | 多文件加载器把 `lib/a/X.x`、`lib/b/X.x` 并入同一翻译单元 |
| f2 | 接受 | **接受（rc=0）** | 与 F2 修复一致 |
| f3 | `RES-103` | `RES-102` 类型 `X` 重复 | 同上 |
| c1 | `RES-103` | `RES-102` 类型 `X` 重复 | 跨包同名类被扁平合并 |

去掉无关的 `lib.b` 导入后（`lib.a.X as P` + `lib.a.Y as P`），CLI **静默通过**（rc=0，
无诊断）。即：**导入别名诊断目前只在 sema `AnalyzeWithDeps` 面生效，CLI 路径未接**。

边界归属：
- `impl/internal/codegen/multifile.go` 的加载器注释已声明“符号在同一翻译单元内扁平链接，
  §3.4 的包前缀属后续切片”；跨包同名类冲突（`RES-102`）是该切片的已知缺口。
- CLI 未调用依赖分析，属原验收单“未跑清单”第 3 条，**不是 F1/F2/F3 的回归**。
- 建议另开卡：CLI 接入 `AnalyzeWithDeps` + 加载器保留包前缀。未开卡前不得据此改判 PKG-01。

---

## 六、证据路径

- Go 用例原始日志：`evidence/QA1-verify-2026-11-07/pkg-go.log`
- CLI 原始输出：`evidence/QA1-verify-2026-11-07/pkg-cli.log`
- 被测 sha：`evidence/QA1-verify-2026-11-07/pkg-sha.txt`（`1ca2153…`）
- 用例副本：`difftest/anchors/cases/qa2_pkg_accept_test.go`、`difftest/anchors/cases/pkg/`
- 原独立用例：`evidence/M1-PKG-01-qa/qa2_independent_test.go`
- 执行器：`difftest/anchors/run-pkg.sh`

---

## 七、未跑 / 边界

1. 多包代码生成（`RES-109`）与非默认包入口未验（多包编译未支持）。
2. 依赖包自身的缺失导入诊断未单测（`Package` 只带导入路径）。
3. 变异 / 覆盖率 / 性能未跑（不属本卡）。
4. CLI 导入诊断见 §五，单独挂账，不并入 PKG-01 判定。
