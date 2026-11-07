# 回执：S2-E4 STRUCT-01 可空值字段（A02）

- 卡片：STRUCT-01 唯一缺口（A02 嵌套值 struct + `Int?` 字段编译路径）
- 提交：`438c28b`（pod/e4-codegen → main 合并）
- 结果：A02 compiled `1\n5`（与 interp 一致）；其余 STRUCT-01 用例保持。
- 顺序：先红后绿。

## 一、红 → 绿

| 用例 | 修前（红） | 修后（绿） |
|---|---|---|
| A02 `Outer { Inner inner; Int? opt = null }`；`print(o.inner.v)`、`o.opt=5`、`print(o.opt)` | `codegen：可空表达式 *xfront.Member 未支持（M6-B0-05 范围）` | `1` / `5` |
| `struct S { Int? v = 1; }` + `print(s.v)`；`s.v=null` | 同上 | `1` / `null` |
| 嵌套 struct 字段初始化/赋值 | 已由前卡支持；本次补 `fieldInitValue` 值 struct 分支 | 保持 |

回归：`go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1` 全绿。

## 二、实现要点

- `containers_expr.go::optExpr`：
  - `*xfront.Member`：按 struct/类字段解引用（`o.field` / `o->field`），可空字段直接取 wrapper；
  - 基础值/字面量：`optWrap` 生成 `(xn_opt_i){1, v}` / `(xn_opt_b)` / `(xn_opt_s)`；
  - `null` → `{0,0}`；Map.get 保持既有。
- `classes.go::fieldInitValue`：可空类型与嵌套 struct 值字段初始化。
- `classes_expr.go::emitFieldAssign`：可空字段赋值（`o.opt = 5` / `null`）与嵌套 struct 值赋值；struct/类两条路径一致。
- `print` 既有 `xn_opt_*` 分流不变（`null`/值）。

## 三、验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestS2STRUCT01' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
```

## 四、边界

- 可空 struct 本身（`T?` 其中 T 为 struct）仍不在本卡；`Int?` 等值可空字段已覆盖。
- 容器/泛型中的可空值字段组合属后续卡。
