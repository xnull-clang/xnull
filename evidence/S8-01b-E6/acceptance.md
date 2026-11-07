# S8-01b 自检结论（清单 schema 语义校验，PROJ-01）

## 交付

`impl/internal/manifest/validate.go`（新）：对单份清单做 S8 §3.2 结构校验，并接入 `Load`（继承链每个文件都校验）。

| 判据 | 实现 | 诊断码 |
|---|---|---|
| 骨架/坐标 GAV + packaging | 四字段必须由工程自声明（不从 parent 继承） | XPD-301 |
| 未知段落/字段 | 白名单 schema（project/parent/modules/properties/dependencyManagement/dependencies/repositories/build/plugins/profiles/configuration/link/libraries…） | XPD-201 |
| 段落/字段重复 | 非可重复块的第二次出现、同段字段重复、project 重复 | XPD-202 |
| 容器段落条目 | `dependencies→dependency`、`repositories→repository`、`plugins→plugin`、`modules→module`、`libraries→library`、`profiles→profile`、`exclusions→exclusion`、`resources→resource` | XPD-203 |
| 坐标重复 | `dependencies` 与 `dependencyManagement.dependencies` 内同坐标 | XPD-302 |
| 位置 | 所有诊断带 file:line:col（取 xpd 节点位置） | — |

## 验证

| 项 | 结果 |
|---|---|
| 红 | 实现前 schema 用例全 FAIL（未知段落/字段返回 `[]`，见 `red.txt`） |
| 绿 | `go test ./internal/manifest -count=1` → **ok**（schema 11 子用例 + 既有继承/变量/profile/依赖用例） |
| 位置 | `TestSchemaPositions`：未知字段落在 `xnull.project:6` |
| xpd 回归 | `go test ./internal/xpd` → ok |

## 缺口

1. schema 不校验「枚举字段取值」（如 `packaging` 只允许 app/library/pom/starter）；非本卡判据，留 S8 其余锚点。
2. 依赖/插件坐标语法（`groupId:artifactId`）未校验形态。
3. `lock` 文件 schema 由 `LoadLock` 单独校验，未复用本 schema。
