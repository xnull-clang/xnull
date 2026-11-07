# 回执：S2-E4 INT-01 try 成员调用

- 卡片：INT-01 A01（编译路径 `try r.get(false)`）
- 提交：`7181fda`（pod/e4-codegen → main 合并）
- 结果：A01 compiled 与 interp 逐字节一致：
  `m-err / m-defer / dR / outer-defer / outer-err / caught:bad`。
- 顺序：先红后绿。

## 一、红 → 绿

| 用例 | 修前（红） | 修后（绿） |
|---|---|---|
| `Int v = try r.get(false)`（`get` 为类成员方法，返回 `Result<Int,String>`） | `codegen：try 调用目标 *xfront.Member 未支持` | 正常；失败时 `m-err/m-defer`，`r` 释放触发 `dR`，外层 `outer-defer/outer-err`，main 捕获 `caught:bad` |
| `Result<...>` 方法返回 | 方法体未声明 `xn_ret`（生成 `use of undeclared identifier xn_ret`） | 声明并按 `hasResult` 处理 |
| 嵌套块内 `return`/`try` 传播 | 只执行当前块 defer，祖先块 `defer/errdefer` 丢失 | 沿 `scope.parent` 执行全部祖先 defer（LIFO） |

回归：`go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1` 全绿。

## 二、实现要点

- `emitTryInto`：
  - 支持 `*xfront.Member` 调用目标：类/结构体/协议/工厂方法（含 `methodCall` 的
    实参求值与返回类型）；
  - 保留顶层函数 `try f()` 路径；错误目标仍显式报错。
- `genMethod`：返回类型为 Result 时声明 `xn_ret`、设置 `hasResult`，自然落空返回零值。
- `scope.parent`：`newChild` 建立父链，`emitCleanup` 从最内层块向外执行所有 defer；
  块正常退出的清理仍只执行本块 defer（不提前触发外层）。
- `emitLocalDecl` try 形态登记局部类型，后续读取/打印不报未登记。

## 三、验证

```bash
cd impl
go test ./internal/codegen/ -run TestS2INT01TryMemberCall -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
```
