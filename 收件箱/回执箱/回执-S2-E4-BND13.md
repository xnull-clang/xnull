# 回执：S2-E4 BND-13 / EXT-01 扩展方法

- 卡片：BND-13 + EXT-01（extension 扩展方法 codegen）
- 提交：`e4b57d4`（pod/e4-codegen → main 合并）
- 顺序：先红后绿。
- 范围：同包非泛型目标、只加方法、静态派发、不进 vtable、不得作协议实现；
  重复/同签名/协议实现违规/泛型目标拒绝。

## 一、红 → 绿

| 用例 | 修前（红） | 修后（绿） |
|---|---|---|
| `extension Device { String label(){...} }` + `d.label()` | `codegen：顶层声明 *xfront.ExtensionDecl 未支持` | `L:x` |
| struct 扩展 `extension P { Int twice(){...} }` | 同上 | `6` |
| singleton 扩展 `extension S { Int twice(){...} }` | 同上 | `4` |
| 重复扩展方法 / 与已有方法同签名 | —（未支持） | EmitC 显式报错 |
| 扩展方法作协议实现（类未声明实现） | — | 协议槽解析显式拒绝（`扩展方法不能作协议实现`） |
| 泛型目标 `extension Box` | — | 显式报错 |
| 扩展方法进入 vtable | — | 测试断言 `xn_init_vtables` 内无 `_ext_` |

回归：`go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1` 全绿。

## 二、实现要点

- `impl/internal/codegen/extension.go`：
  - `collectExtensions`：解析目标（class/struct/singleton/数据 enum），排除协议/
    简单枚举/泛型/泛型实例化；只接受实例方法（拒绝 static/deinit/泛型方法）。
  - 方法 C 名 `xn_<Target>_ext_<method>_<argc>`，登记进目标 `classInfo.methods`，
    参与普通方法解析与继承静态派发。
  - 与目标已有/继承方法同名同签名、扩展之间重复 → 编译错误。
  - `emitExtensionProtos`（前向声明）与 `emitExtensions`（方法体）。
- `protocol.go`：vtable 槽解析遇到 `m.ext` 显式拒绝（扩展方法不能作协议实现），
  正常方法仍按协议槽填入；扩展方法不进 vtable。
- 扩展不改变目标布局/内存策略；不接受字段/构造器/`deinit`/静态方法。

## 三、与 E2 的接口

- 同包限制/跨包扩展拒绝、目标可见性、扩展方法可见性（默认 public、不可
  private/protected）由 sema 判定；codegen 只校验目标种类/非泛型/方法形态。
- 协议实现检查（类必须由声明/继承方法满足）由 sema 保证；codegen 在 vtable
  生成时兜底拒绝扩展实现。
- 重载：codegen 当前按方法名唯一（与类方法同一限制）；扩展同名不同参数在
  sema 允许时，codegen 显式报错（不静默）。

## 四、验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestS2BND13' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
```
