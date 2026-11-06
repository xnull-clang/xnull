# M6-B0-05 容器与字符串成员覆盖矩阵

基线：`pod/e3-interp` `e1012af`。用例集：39 项成员 × 解释/编译两条真实 CLI 路径（含 sema），
逐字节比对 stdout 与退出码。运行：`./matrix.sh before|after`。

## 汇总

| 阶段 | 通过单元 | 双路径全通 |
| --- | --- | --- |
| before | 64 / 78（82.1%） | 27 / 39 |
| after  | 65 / 78（83.3%） | 27 / 39 |

after 的 13 个失败单元：编译侧 12 项、解释侧 1 项（`List.remove`，被 sema 的 `void` 返回类型挡住，
运行时已修，见下）。

## 解释器侧已修（本卡，红→绿）

| 项 | 规范 | 修前 | 修后 |
| --- | --- | --- | --- |
| `Map.get` 缺键 | §9.5 返回 `V?`，缺键 `null` | `fatal` 退出 134 | 返回 `null` |
| `List.remove` | §9.4 删除并返回被删元素 | 返回 `null` | 返回被删元素 |
| `List.insert` 越界 | §9.4 合法位置 `0..length`，越界 panic | 静默钳制 | `fatal`（134） |

- 红：`before/interp-gap-red.log`（3/3 FAIL）
- 绿：`after/interp-gap-green.log`（3/3 PASS）、`after/interp-full.log`（`go test ./internal/interp/...` ok）
- 代码：`impl/internal/interp/values.go`；测试：`impl/internal/interp/interp_test.go`

## 剩余项（不在本域）

12 项全部是 codegen 缺口，清单见 `收件箱/CEO2/缺口清单-M6-B0-05-codegen-2026-11-07.md`：
`String.split`、`String.replace`、`T[].join`、`List.insert`、`List.remove`（值返回）、`Map.get`、
`Map.getMissing`（`Int?` 类型后缀）、`Map.keys`、`Map.values`、`Set.at`、`Set.remove`、`Set.clear`。

## 三个“未覆盖分支”探测

| 分支 | 结论 | 证据 |
| --- | --- | --- |
| `containers_expr.go:97` | 当前不可达：嵌套数组/不支持的容器元素在 `cType`（`codegen.go:419`）先失败 | `before/branch-nested-array.*` |
| `containers_expr.go:102` | 同上（Map 字面量目标类型在 `cType` 阶段即被拒） | 同上 |
| `codegen.go:1411` | 矩阵未命中；可命中的相邻缺口是 `strExpr` 缺 `Index`/`TupleMember` 接收者（走 `:1415`） | `before/branch-index-recv.*`、`before/branch-tuple-recv.*` |

## 判定口径

- `PASS` = 退出码 0 且 stdout 与期望逐字节一致；编译路径失败含 sema 诊断与 codegen 诊断。
- 单路径 PASS/FAIL 独立计分，因此同一项可能出现“解释 PASS / 编译 FAIL”。
- `List.remove` 的解释路径当前 FAIL 是 sema 缺口（E2 域），不是解释器运行时缺口。
