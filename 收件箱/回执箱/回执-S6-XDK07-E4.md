# 回执：S6 XDK-07 codegen 特化容器（E4）

- 卡片：XDK-07 编译端到端（`收件箱/门/S6-XDK07-E2E.md` G1–G4）
- 提交：`892c46e`（仅 pod/e4-codegen；已同步 main 的 XDK-07 用例/签名）
- 顺序：先红后绿：`evidence/S6-XDK07/red.log`（compiled BLOCKED：
  `可空表达式成员 pop 未支持`）；`green.log`（sema/interp/compiled 全 PASS）。

## 一、红 → 绿（E2 交接 G1–G4）

| 缺口 | 修前（红） | 修后（绿） |
|---|---|---|
| G1 `T?` 方法返回 | `可空表达式成员 pop 未支持` | `RingBuffer.pop/peek`、`OrderedMap.get`、`BTreeMap.get`、`PriorityQueue.peek/pop` 返回 `xn_opt_*`；可选表达式绑定临时（避免二次求值） |
| G2 `return null` | `返回表达式 NullLit 未支持` | 可空返回零值 `{0,0}`；判空后 `T?→T` 显式收窄 |
| G3 函数类型字段/参数 | `类型 FuncTypeRef 未支持` | 按签名去重 typedef；泛型替换覆盖 FuncTypeRef；无捕获 lambda → C 函数；`self.less(a,b)` 间接调用 |
| G4 数组返回/容器成员分派 | `keysArray 接收者不是容器` | `new T[n]` 定长 GC 数组 + 零初始化；类方法返回容器/数组；有实参时优先方法（不再误取同名字段） |

## 二、验证

```bash
cd impl
go test ./internal/cli/ -run TestXDK07 -count=1 -v
# PASS: SemaSurface / InterpE2E / CompiledE2E
```

- `collections_basic.x` 与 `collections_nonnull.x` 编译输出与 `.expect` 逐行匹配
  （19 行 / 17 行）。
- 全量：codegen / ffi / cli / interp / sema 全绿。

## 三、实现要点

- 可空：`emitReturn` 可空分支（null/值）、`optExpr` 类方法分支（临时绑定）、
  标量返回时 `T?→T` 取 `.v`。
- 函数类型：`g.fnTypeC` 生成 `typedef ret (*name)(params);`（按签名去重，位置
  在类前向之前）；`emitLambdaFn` 生成无捕获闭包体（lateFns/lateProtos）。
- 数组：`arrayNewExpr` 发 `arr_new(n)` + `len=n` + `memset` 零初始化；
  `emitReturn` 容器指针移交；容器局部初始化支持 `new T[n]` 与类方法返回容器。
- 成员分派：函数指针字段发间接调用；有实参时方法优先于同名字段。

## 四、边界

- 闭包捕获外部变量仍显式报错（未装箱 env）；本次用例的 `less` 闭包无捕获。
- 数组为 GC 容器指针（与内建容器一致）；固定长度仅体现在 `len` 语义。
- 函数指针字段未做 `deinit` 清理（无引用计数语义）。
