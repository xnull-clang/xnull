# 回执：S2-E4 enum / struct 发射面

- 卡片：S2 codegen enum + struct（`收件箱/门/S2审计-E4.md` S2-E4-08/09）
- 提交：`5764944`（pod/e4-codegen → main 合并）
- 顺序：先 enum 后 struct；均先红后绿。

## 一、红 → 绿

| 用例 | 修前（红） | 修后（绿） |
|---|---|---|
| 简单枚举 `print(Color.Green)` | `codegen：顶层声明 *xfront.EnumDecl 未支持` | `Green` |
| 枚举 `switch`（无 default） | `codegen：语句 *xfront.SwitchStmt 未支持` | `g` |
| 数据枚举 `Status.Ready` / 字段 / 方法 | 同上（EnumDecl 未支持） | `Ready` / `0` / `1`，项指针身份相等 |
| `struct Point` 赋值复制 | `codegen：顶层声明 *xfront.StructDecl 未支持` | `a.x=1, b.x=9` 副本独立 |
| 嵌套 struct / 传参复制 | 同上 | `o.inner.v=7, c.inner.v=9`；`copyOf(a)` 不改 `a` |

回归：`go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ -count=1` 全绿。

## 二、实现要点

- `impl/internal/codegen/enum.go`：
  - 简单枚举：`typedef int64_t xn_Enum_<N>`；项值按 §8.2（显式/递增）计算；
    `xn_enum_<N>_name` 项名助手用于格式化/插值。
  - 数据枚举：复用 `classInfo`（结构/构造器/方法/deinit 路径）；项全局
    `xn_enum_<N>_<Item>`，启动期 `xn_init_enums()` 按声明序构造；字段访问与
    方法调用走类路径；`==`/`===` 指针身份。
  - `Enum.Item` 访问统一在 `intExpr`/`exprType`/`recvCName` 解析。
- `impl/internal/codegen/struct.go`：
  - 无头按值 C 结构体 `xn_Struct_<N>`；构造器返回结构体值（隐式无参 + 主/普通）；
    方法 `T *self` 静态派发；嵌套 struct 内联。
  - 赋值/传参/返回/局部初始化用 C 结构体赋值，天然满足 §3.3 整值复制。
- `switch`（S1 §6.8）通用发射：`do { if / else if ... } while (0)`，无贯穿；
  `break` 退出 switch；支持整数/简单枚举/字符串 case。
- 测试：`TestS2EnumSimpleAndSwitch`、`TestS2EnumDataSingleton`、
  `TestS2StructValueCopy`。

## 三、边界（未纳入本卡）

- 枚举穷尽性/重复 case/未知 case/default 位置（E2 sema，S2-BND-06）。
- 数据枚举 GC 语义（当前 ARC；E5 MEM-01/02）、`toString()` 覆盖、项前向引用检查。
- struct 可空值字段、struct 进入容器/数组/泛型实参（mangle 未扩）；sret ABI。
- 协议/继承与 enum/struct 的组合限制（sema 主责）。

## 四、验证命令

```bash
cd impl
go test ./internal/codegen/ -run 'TestS2Enum|TestS2StructValueCopy' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ -count=1
```
