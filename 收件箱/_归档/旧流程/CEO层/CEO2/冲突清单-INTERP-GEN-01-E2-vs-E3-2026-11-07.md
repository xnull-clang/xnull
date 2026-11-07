# 冲突清单：pod/e2-sema × pod/e3-interp（interp/tuple 相关）

> 只读比对结论。已用 `git merge-tree --write-tree --messages pod/e3-interp pod/e2-sema` 预演（exit=1）。
> **未合并、未 checkout、未改 E2 分支**；E3 侧未改 `values.go`。

## 基线

| 分支 | HEAD | 说明 |
|---|---|---|
| `pod/e3-interp` | `e1012af` | M1-TUPLE-01（`461a47a`）+ M1-GEN-01 泛型重载（`e1012af`） |
| `pod/e2-sema` | `53c32c7` | M1-TUPLE-01 完整版（interp + sema） |

## 冲突（仅 1 个文件）

`impl/internal/interp/interp.go` — `CONFLICT (content)`，一个冲突块覆盖两个语义区域：

| # | E3 版本位置 | E2 版本位置 | 内容 | 处理建议 |
|---|---|---|---|---|
| 1 | `interp.go:692-695` | 同 | `evalBinary` 的 `case "==="` / `case "!=="`：E3 调 `identical`，E2 调 `valuesIdentical` | 保留一份实现，统一改名 |
| 2 | `interp.go:854` | `interp.go:853` | `valuesEqual` 之后同一插入点：E3 新增 `identical`，E2 新增 `valuesIdentical` | 删除重复函数，调用点改同名 |

- 两个函数语义等价：元组逐元素同一性、值类型比内容、引用类型比句柄、`null === null` 为 true。
- `valuesEqual` 的 `case vTuple` 两版内容逐字相同，可自动合并，不构成独立冲突。
- **结论**：这不是语义冲突，是同一功能的双实现命名冲突；解决成本 ≈ 1 次改名 + 删 1 个函数。

## 不冲突但需知会（自动合并）

| 文件 | E2 改动 | E3 改动 | 结论 |
|---|---|---|---|
| `impl/internal/interp/interp.go` | `scope.define/assign` 走 `cloneTupleValue`；`assignTo` 支持 `TupleMember` | `evalCall` 重载选择（`selectFunc`，GEN-01） | 不同 hunk，自动合并 |
| `impl/internal/interp/values.go` | 新增 `cloneTupleValue`；`evalTupleMember` 支持 `?.N` | 无改动 | 自动合并；建议以 E2 为准 |
| `impl/internal/interp/tuple_test.go` | 新增文件 | 无 | 自动合并 |
| `impl/internal/interp/interp_test.go` | 无改动 | 新增 tuple / GEN-01 测试 | 自动合并 |
| `evidence/M1-TUPLE-01/` | 完整证据集 | `interp-*.log` 三份 | 文件名不重叠，自动合并；同一张卡两套证据需去重口径 |

## 风险提示

1. E2 的 `cloneTupleValue` 改变了元组赋值/传参的值语义；E3 的相等/同一性测试在该语义下仍成立，合并不回退。
2. 若先合 E2 再合 E3，E3 的 `identical` 会与 E2 的 `valuesIdentical` 并存，必须人工删一个，否则重复实现、后续漂移。
3. E2 分支同时改了 sema；`pod/e2-sema` 未 push 未合并，L1/L2 门禁仍由 CEO1/CEO2 签。

## 复现命令（只读）

```bash
cd /Users/vjs/Desktop/XNull-Lang/wt/e3-interp
git merge-tree --write-tree --messages pod/e3-interp pod/e2-sema
git diff main...pod/e2-sema -- impl/internal/interp/
```
