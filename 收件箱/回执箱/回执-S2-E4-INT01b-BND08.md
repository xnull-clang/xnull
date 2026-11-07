# 回执：S2-E4 INT-01b + BND-08（ADR-005 缩线两卡）

- 卡1 INT-01 codegen：`b2deb74`
- 卡2 BND-08 codegen：`16e8e1b`
- 顺序：先 INT-01b，后 BND-08；每卡单独 commit。均先红后绿。

## 卡1：INT-01 codegen（b2deb74）

| 子项 | 红 | 绿 |
|---|---|---|
| A02 `Result<Device, String>` | `Result 值类型暂支持 Int/Bool，got Device` | Ok 类值/Err 均发射；`f-err/f-defer/f-caught:boom` |
| A02b `Result 表达式目标 *xfront.Member` | `codegen：Result 表达式目标 *xfront.Member 未支持` | 工厂/类/struct/协议成员返回 Result 可解析 |
| A03 类字段 `Color c = Color.Green` | `类字段 Holder.c 的初始化式访问了成员 Green` | `g` / `b`（switch 同步） |

实现：
- `resultName`/`resultMemberC`：Result 值标签支持类/struct/枚举/String；typedef 移到
  类/struct/枚举前向声明之后。
- `resultOkValue`：Ok(new Device(...)) 走类值（+1 retain），支持 struct/String/枚举/协议。
- `resultExpr` 支持 `*xfront.Member` 调用目标（工厂/类/struct/协议方法返回 Result）。
- 汇总类/struct/枚举/单例/工厂方法返回与局部 Result 实例（修复 xn_ret 类型/未声明）。
- `validateFieldInit` 放行枚举项常量；`fieldInitValue` 支持枚举字段。

## 卡2：BND-08 codegen（16e8e1b）

| 子项 | 红 | 绿 |
|---|---|---|
| 跨包 factory 公开静态方法 `Device.make(n)` | `codegen：未登记标识符 Device` | 跨包 import 后输出 `x` |
| 跨包 factory 私有构造 `new Device(n)` | 同源 | 输出 `x` |
| factory 方法使用 self | —（无绑定） | EmitC 显式报错，不生成坏 C |

实现：
- 类/struct/单例/数据枚举方法支持 `static`：原型/定义无 `self` 参数，方法体无 self 上下文。
- `staticClassCall`：`ClassName.staticMethod(...)` 在 exprType/intExpr/strExpr/
  classCallExpr/emitExprStmt/resultExpr/emitTryInto 全路径解析。
- 跨包 Target：`import lib.device` 合并单元后，Target 类静态方法/私有构造可发射。
- factory 方法仍无 self/super 绑定（E2 sema 对齐）。

回归：`codegen/... + cli + interp + sema` 全绿。

## 与 E2 的接口

- factory/singleton 名称与成员解析（`DeviceFactory.create`）当前 sema 仍报 RES-101；
  codegen 用例以 bypass-sema 覆盖。E2 接入后 CLI 端到端自动生效。
- 静态方法可见性（public/private）、factory Target 可见性、factory 方法禁止 self 由
  sema 判定；codegen 不提供 self 绑定。
- Result<T> 值类型的可赋值性/错误类型约束由 sema 检查。

## 验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestS2INT01b|TestS2BND08' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
```
