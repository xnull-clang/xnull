# S6-XDK-07 编译端到端交接（E2 → E4）

- 用例：`tests/s6/xdk07/collections_basic.x`（期望 `collections_basic.expect`）
- main 实测：`xnull check` PASS；`xnull run --interp` PASS；`xnull run`（编译）失败于 codegen。
- E2 已完成：collections 成员签名 + `PriorityQueue.less` 函数字段**实参检查**（main 当前对 `pq.less(1,"x")` 不报错，本分支报 `TY-101`）。
- E4 待接（按出现顺序，均为 codegen 面，未跨域修改）：

## G1 可空方法返回/成员
- 复现：`collections_basic.x` → `codegen：可空表达式成员 pop 未支持（M6-B0-05 范围）`
- 接口：`RingBuffer.pop/peek`、`OrderedMap.get`、`BTreeMap.get`、`PriorityQueue.peek/pop` 返回 `T?`；需要可空值表示、`T?` 调用的结果落地与后续判空。
- 最小骨架：`impl/lib/xdk/collections.x` 的四个容器。

## G2 `return null`
- 复现：`class C { Int? maybe() { return null } }` → `codegen：返回表达式 *xfront.NullLit 未支持（M4.1 范围）`
- 接口：可空返回类型 + `return null` 的 C 发射（与 G1 同一表示）。

## G3 函数类型字段/参数
- 复现：`class C { Bool(Int,Int) less; C(Bool(Int,Int) l){ self.less = l } }` → `codegen：类型 *xfront.FuncTypeRef 未支持（M4.1 范围）`
- 接口：`PriorityQueue.less` 字段类型 `Bool(T,T)`、构造器实参、`self.less(a,b)` 间接调用；需要闭包/函数指针字段表示与调用约定。

## G4 返回数组的类方法 / 容器成员分派
- 复现：`collections_nonnull.x` → `codegen：容器表达式成员 keysArray 的接收者 xn_Cls_BTreeMap_i * 不是容器`
- 接口：`OrderedMap.keysArray/valuesArray`、`BTreeMap.keysArray` 返回 `Int[]/V[]`；codegen 需区分“类方法调用”与内建容器成员，并支持数组返回。
- 另：`class C { Int[] arr(){ Int[] xs=[1]; return xs } }` → `返回表达式 *xfront.IdentExpr 未支持`（数组成员返回路径）。

## 验收联动
- E4 修复后，`impl/internal/cli/xdk07_e2e_test.go` 的 compiled 子测试自动从 SKIP 转为输出断言，无需改测试。
- 期望输出见 `collections_basic.expect`（19 行）。
