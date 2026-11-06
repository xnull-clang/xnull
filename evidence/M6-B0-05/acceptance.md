# M6-B0-05 验收结论（执行侧自检，E5/QA 会签待做）

卡片：容器与字符串成员补齐（codegen 主责，清单 `收件箱/CEO2/缺口清单-M6-B0-05-codegen-2026-11-07.md`）。
铁律：`Map.keys/values` 必须与解释器同序（DET-01）；未改既有测试期望。

## 矩阵

| 阶段 | cells（78） | ops 双路径（39） | 说明 |
| --- | --- | --- | --- |
| before（本分支） | 64 | 27 | 复现清单缺口 |
| after（本分支） | 76 | 37 | 余 2 个解释器侧单元（E3 已修未合入） |
| after（合并口径：本分支 + E3 interp） | **78** | **39** | `after-combined.log` |

补充：`extras.sh` 6/6（4 项附带 + 2 项 DET-01 键序），`alternatives.sh` 12/12。

## 12 项直接成员

- [x] `String.split` → `xn_str_split`（空分隔符=整串；字节匹配）
- [x] `String.replace` → `xn_str_replace`（ReplaceAll；空 from 返回原串）
- [x] `T[].join` → `xn_arr_<e>_join`（Int/Bool/String 元素格式化）
- [x] `List.insert` → `xn_arr_<e>_insert`（0..length，越界 fatal）
- [x] `List.remove` 值返回 → helper 返回元素；sema 同批返回元素类型
- [x] `Map.get` → `xn_map_<k>_<v>_get` 返回 `V?`
- [x] `Int?` / `T?` 类型后缀 → `xn_opt_i/b/s` + `print` 支持
- [x] `Map.keys` → 排序（String 按字节、Int 按十进制串、Bool false<true）
- [x] `Map.values` → 按同一排序索引取值
- [x] `Set.at` → `xn_set_<e>_at`（越界 fatal）
- [x] `Set.remove` → Bool（与解释器一致）
- [x] `Set.clear` → `xn_set_<e>_clear`

## 4 项附带

- [x] `+=` / `-=`（标量；String/可空目标显式报错）
- [x] `print(null)` → `null`
- [x] 数组形参 `a[i]` → `&xn_p_a`（`cRef` 前缀）
- [x] `Map.getOr` 动态键不再 panic（`strExpr` 支持容器 get 借用）

## 3 个未覆盖分支

- [x] `containers_expr.go` 数组字面量目标类型不支持：显式诊断 + `TestContainerLiteralTargetErrors`
- [x] `containers_expr.go` Map 字面量目标类型不支持：显式诊断 + 同一测试
- [x] `codegen.go` String 成员接收者不支持：补 `strExpr` 下标接收者（`a[0].length()`）+ `TestStringMemberIndexReceiver`；`p.1.length()` 依赖元组（TUPLE-01 未落地），显式不支持

## 未测项 / 边界

1. `Map.get` 的 `V?` 仅覆盖标量/String（`Int?`、`Bool?`、`String?` 的 print/赋值）；类引用/容器值的可空形态未接。
2. 可空值只支持声明/赋值/print/Map.get；算术、比较、`??`、`as?` 未接。
3. `Map.keys/values` 的排序对类引用键不适用（键仅 Int/Bool/String）。
4. `T[].join` 仅数组；`List.join` 不在解释器语义内。
5. 元组接收者（`p.1.length()`）随 TUPLE-01 一并落地。
6. 本分支矩阵 76/78 的解释器两项由 E3 分支提供；合并后 78/78 已在临时合并口径验证。

## 声明

执行侧自检；E5 会签与 B0 门禁另判。
