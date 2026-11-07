# QA1 锚点复验执行器（GEN-01 / NEG-01 / PKG-01）

原则：不污染任何工作树。每个脚本先把 `--sha` 导出到临时目录，再注入 QA 独立用例，
跑完即删。

## 用法

```bash
cd /Users/vjs/Desktop/XNull-Lang/wt/qa-1

# 全部（默认 main）
bash difftest/anchors/run-all.sh --sha main --out evidence/QA1-verify-$(date +%Y%m%d)

# 单项
bash difftest/anchors/run-gen.sh --sha main
bash difftest/anchors/run-neg.sh --sha main --neg-ref pod/c3-rd3
bash difftest/anchors/run-pkg.sh --sha main
```

## 口径

| 脚本 | 用例来源 | 通过标准 |
|---|---|---|
| `run-gen.sh` | `difftest/gen01/cases.json`（QA1 自写 26 项） | 26/26 |
| `run-neg.sh` | `impl/Tests/neg_test.go`（台账 NEG-01，60 项） | 60/60 |
| `run-pkg.sh` | `cases/qa2_pkg_accept_test.go`（49 子项）+ `cases/pkg/{f1,f2,f3,c1}.x` | 49/49；CLI 例默认只作补充观察 |

PKG CLI 期望：

| 用例 | 期望 | 说明 |
|---|---|---|
| `f1.x` | `RES-103` | 同一别名 `P` 指向 `lib.a.X` / `lib.a.Y` |
| `f2.x` | 接受（rc=0） | `import xdk.net.http` 为合法多级 XDK 包 |
| `f3.x` | `RES-103` | 别名 `Y` 与同包裸导入 `lib.a.Y` 撞名 |
| `c1.x` | `RES-103` | 同一别名 `P` 指向 `lib.a.X` / `lib.b.X` |

`RES-102`（包内类型重复声明）不是 §3.5 要求的别名消歧诊断。

**CLI 例不计入 PKG-01 的 49 项门禁**：`PKG-01` 的验收面是 sema 的
`AnalyzeWithDeps`（原验收单“未跑清单”第 3 条已声明 CLI 未接导入诊断）。
需要连 CLI 一起卡时加 `--require-cli`；当前 `f1/f3/c1` 在 CLI 多文件路径仍
`RES-102`（同名类跨包被扁平合并）或静默通过，属加载器包前缀缺口，另记。

## 注意

- NEG 用例文件目前只在 `pod/c3-rd3`；`--neg-ref` 默认取该分支。
- `run-pkg.sh` 的 Go 用例拷入导出树的 `impl/internal/sema/`，不改被测分支。
- 所有构建/运行需 `go` 与 `cc`；`xnull build` 由脚本自动指向导出树的
  `impl/runtime`（`XNULL_RUNTIME`）。
