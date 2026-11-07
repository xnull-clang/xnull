# 回执：S2-E4 BND-07 singleton / BND-08 factory（codegen）

- 卡片：BND-07 / BND-08（E1 语法 AST 已合入 main）
- 提交：`827d5a8`（pod/e4-codegen → main 合并）
- 范围：先 singleton 后 factory；extension/annotation 后置。
- 说明：本卡只做 codegen 发射面；sema 对 singleton/factory 的名称/可见性尚未接入
  （CLI 当前在 sema 报 `RES-101 未定义的名称 AppInfo`），codegen 测试以
  `ParseUnit + EmitC` 绕过 sema 验证发射面，并给出 E2 接口见 §三。

## 一、红 → 绿

| 用例 | 修前（红，EmitC 面） | 修后（绿） |
|---|---|---|
| `singleton AppInfo { String name="XNull"; Int n=3; Int twice(){...} }` + `AppInfo.instance.name/twice()` | `codegen：顶层声明 *xfront.SingletonDecl 未支持` | `XNull` / `6`；`instance.n=4` 后 `8` |
| `factory DeviceFactory for Device { static Device create(String) }` | `codegen：顶层声明 *xfront.FactoryDecl 未支持` | `A` |
| `factory BoxFactory for Box { static Box<T> create<T>(T) }` + `create<Int>(9)` | 同上 | `9` |

回归：`go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ ./internal/xfront/ -count=1` 全绿。

## 二、实现要点

- `impl/internal/codegen/singleton.go`：
  - `xn_Single_<Name>` 对象（ARC；GC 语义由 E5）、全局 `xn_single_<Name>`；
  - 启动期 `xn_init_singletons()` 在顶层字段之后、`main` 之前构造实例并执行字段初始化式；
  - `Name.instance` 解析为全局实例；字段/方法经实例静态访问；
  - `new 单例` 显式拒绝；静态字段/方法暂为显式边界。
- `impl/internal/codegen/factory.go`：
  - `static` 工厂方法发射为 `xn_Factory_<F>_<m>`；`Factory.m(...)` 解析调用；
  - 泛型工厂方法注册到既有单态化表（显式类型实参 `create<Int>`）；
  - 泛型目标 `new Box<T>` 复用 BND-12 类实例化；
  - 工厂不是类型、不分配对象；只发射方法。
- `exprType`/`intExpr`/`strExpr`/`classCallExpr`/`emitExprStmt` 增加工厂调用与单例 instance 解析。
- 测试：`TestS2BND07Singleton`、`TestS2BND08Factory`、`TestS2BND08FactoryGeneric`。

## 三、与 E2 的接口（本卡未改 sema）

sema 接入后 CLI 端到端才绿，需要：

1. **名称登记**：`SingletonDecl`/`FactoryDecl` 名进入顶层类型命名空间；
   `AppInfo.instance` 成员可解析（类型 `AppInfo`），`Factory` 不能当类型使用。
2. **访问约束**：`instance` 只读、不可 null、不可手动声明；单例禁止 `new`、
   泛型、继承、协议、构造器；单例初始化前向引用拒绝（§9.2/§9.4）。
3. **工厂调用**：`Factory.m(args)` 按方法名+元数/类型解析；泛型方法类型实参
   个数校验；返回类型约束（Target/父类/协议/Result，§10.2）。
4. **可见性/私有构造**：同包 factory 可访问 Target 私有构造器；跨包仅公开成员
   （§10.3）；`protected` 方法在 factory 中非法。
5. 若 sema 需要 AST 缺失字段（如 singleton 的 `instance` 合成成员），按 AST 层
   补；codegen 不反向依赖 sema 内部结构。

## 四、边界

- extension / annotation codegen 后置（本卡未做）。
- 单例静态字段/方法、GC 策略（E5）；工厂跨包/可见性（E2）。
- 工厂方法内 `self`/`super` 禁止由 sema 检查；codegen 不提供这些绑定。

## 五、验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestS2BND07|TestS2BND08' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ ./internal/xfront/ -count=1
```
