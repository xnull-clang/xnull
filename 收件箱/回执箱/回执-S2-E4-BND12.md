# 回执：S2-E4 BND-12 泛型类单态化

- 卡片：BND-12（泛型类 `class Box<T>` codegen 半边）
- 提交：`ad44263`（pod/e4-codegen → main 合并）
- 顺序：先红后绿。

## 一、红 → 绿

| 用例 | 修前（红） | 修后（绿） |
|---|---|---|
| `class Box<T> { T v; T get() {...} }` + `Box<Int>` / `Box<String>` | `codegen：类型 T 未支持` | `7` / `x` |
| 方法实例名 | — | 生成 `xn_Cls_Box_i_get`、`xn_Cls_Box_s_get`（不同实例独立 C 名） |
| 字段替换 | — | `Box<Int>` 字段 `int64_t v;`；`Box<String>` 字段 `rt_string * v;` |
| 嵌套泛型 `Nest<T>{ Box<T> inner; }` | 同上（T 未支持） | `Nest<Int>` 输出 `5` |
| 多类型参数 `Pair<A,B>` | 同上 | `3` / `y` |

回归：`go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1` 全绿。

## 二、实现要点

- `impl/internal/codegen/generic_class.go`：
  - `ensureClassInstance(name, args)`：按类型实参编码实例名（`xn_Cls_Box_i`），
    建立 `T → 实参` 替换表，收集字段/构造器/方法；实例登记到 `classInsts`
    并以 `Box_i` 键进入 `classes` 供 `classOfC` 反查。
  - `withSubst`：实例生成（结构/构造器/方法/方法调用/返回类型）统一在替换表下求值。
  - 嵌套泛型：实例字段 `Box<T>` 在收集期递归 `cType → ensureClassInstance`。
- `cType`：`Box<Int>` → 实例 C 类型；缺参/多参显式报错。
- `emitNewClass` / `exprType New`：`new Box<Int>(...)` 解析到实例构造器。
- `methodProto` / `genMethod` / `methodCall` / `methodRetC` / `emitClassCtor`：
  在实例替换表下生成签名与调用点。
- 泛型声明本身不发 C 结构/方法；只发被使用的实例。

## 三、与 E2 的接口（本卡未改 sema）

codegen 只消费 AST 的 `NamedType.Args`，需要 sema 保证：

1. `Box<...>` 实参个数 == `TypePars` 个数；实参必须是类型（不能 void）。
2. 残留类型参数（未解析的 `T`）不得进入实例化；推断未完成应报错而非放行。
3. 泛型类作为**值字段**的实参限制（BND-04）由 sema 判；codegen 只按类型发射。
4. 若后续支持 `Box b = new Box(1)` 的实参推断，sema 需把推断结果写回
   （当前 AST 无泛型类推断回写字段，codegen 只支持显式实参）。
5. 泛型类 + 继承/协议：codegen 当前显式报错（边界），待 E2 规则确定后另卡。

## 四、边界（未纳入本卡）

- 泛型类继承/实现协议、泛型类作结构体字段/容器元素的全部实参组合。
- 实例数量上限与确定性排序已按发现顺序；跨模块 ABI 未定。
- 泛型结构体、泛型枚举（E2/后续卡）。

## 五、验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestS2BND12' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
```
