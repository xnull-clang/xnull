# 回执：S2-E4 BND-15 + EXT-01 补口

- BND-15 集成 codegen：`c5bcc4e`
- EXT-01 合法扩展重载补口：`f4d1d44`
- 纪律：仅 pod/e4-codegen，未 merge main。
- 顺序：先 BND-15，后 EXT-01；均先红后绿。

## 一、BND-15（c5bcc4e）

| 集成用例 | 红 | 绿 |
|---|---|---|
| Result/try/defer × factory × 类对象：`Device d = try F.open(ok)` | `类实例局部初始值只支持 new/调用` / Result 值类型类不兼容 | `f-defer / ok / false / f-err / f-defer / boom` |
| Result/try × 枚举穷尽 switch × struct：`Color c = try pick(true)` | try 初值不支持枚举/struct；跨 Result 值类型传播类型不兼容 | `g / 9 / false` |
| try 赋值（非声明）到对象：`d = try F.open(true)` | 赋值路径无 try 解包 | `ok / false` |

实现：
- `emitLocalDecl` 通用 try 解包（Result<T,String> → 类/struct/枚举/协议/String/标量），
  所有权按类型 retain/release。
- `emitTryInto` 允许外层 Result 值类型与 try 目标不同：置零后转移 Err 通道。
- `exprType` 支持 Result 成员 `value` / `error` / `unwrapOr` 与类/struct/枚举成员类型。
- 测试：`TestS2BND15TryFactoryObject`、`TryEnumStruct`、`TryAssignObject`。

## 二、EXT-01 补口（f4d1d44）

| 用例 | 修前（红） | 修后（绿） |
|---|---|---|
| 合法扩展重载 `f()` + `f(Int)`、`g(Int)` + `g(String)` | codegen 以同名/同签名误拒 | `1 / 2 / i1 / sx` |
| 重复/同签名拒绝 | codegen 越权拒绝 | 交由 sema（E2）；codegen 不拒绝合法重载 |

实现：
- 目标类型维护 `overloads` 表；扩展方法 C 名按声明序唯一化（`_ext_<m>_<n>`），
  同名不同参数不再撞名。
- `methodFor` 按实参元数选择；同元数时按实参类型匹配参数 C 类型；调用点
  （类/struct/单例/数据枚举/协议/Result/try）统一使用该方法选择。
- vtable 槽解析仍用协议签名的参数元数选择，扩展方法不进入 vtable。
- 测试：`TestS2EXT01ExtensionOverloads`（1/2/i1/sx）；既有 BND-13 rejects
  移除 codegen 层的重复/同签名拒绝（归 sema）。

## 三、回归与验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestS2BND15|TestS2EXT01|TestS2BND13' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
```

结果：全绿。

## 四、与 E2 的接口

- 重复/同签名/跨包/泛型目标/deinit/静态方法等扩展负例由 sema 报错（E2）；
  codegen 不再以自身错误替代语义诊断，只保留形态兜底（目标种类/静态等）。
- 协议实现检查 sema 主责；codegen vtable 发射兜底。
- BND-15 的 factory 名称/成员解析依赖 sema（当前 pod 分支未合 main 的 E2 语义；
  集成测试以 bypass-sema 覆盖 codegen 发射面）。
