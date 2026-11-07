# 回执：S2-E4 SINGLE-01 codegen 面

- 卡片：SINGLE-01（instance 只读/无 new/不实现协议/启动初始化/静态字段与前序单例引用）
- 提交：`a9144c1`（仅 pod/e4-codegen，未 merge main）
- 背景：BND-07 已 7/7；本卡补 SINGLE-01 独立矩阵中 codegen 缺口。

## 一、红 → 绿

| 用例 | 修前（红） | 修后（绿） |
|---|---|---|
| `singleton S { static Int base=7; static Int twice(){return base*2} Int port=base+1 }` | `单例静态字段暂未支持` / `单例静态方法暂未支持` | `Config.base=7`、`twice()=14`、`port=8` |
| `singleton Derived { Int v = Config.instance.port + 1 }` | `字段初始化式访问了成员 port`（单例初始化校验误拒） | `v=9`（启动期按声明序引用前面单例） |
| `AppInfo.instance = null` | codegen 未显式拒绝（落到未登记接收者） | `单例 instance 只读，不能赋值` |
| `AppInfo a = new AppInfo()` | 已拒绝 | 保持显式拒绝 |
| `singleton S implements P` | parser/sema 拒绝 | 不在 codegen 面 |
| 启动前初始化 | 实例初始化在 main 前 | 保持（`xn_init_singletons` 于 main 前） |

回归：`go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1` 全绿。

## 二、实现要点

- `singleton.go`：
  - `SingletonDecl` 字段按 `Mod.Static` 分流：实例字段 vs `staticFields`；
    静态方法按 `static` 发射（无 self）。
  - `emitSingletonForwards` 声明 `xn_static_<S>_<field>`；`xn_init_singletons`
    先按声明序初始化全部静态字段，再按声明序构造单例实例（S2 §9.2）。
  - 实例字段初始化允许引用前面单例（`A.instance.field`）与静态字段；
    单例专用初始化不套用类字段初值限制。
- `scope.staticRefs/staticTypes`：单例静态方法/初始化式中的裸静态字段名解析为
  C 全局变量（局部/参数仍优先）。
- `singletonStatic`：`S.field` 读写解析；`emitAssign` 拒绝 `S.instance = ...`。
- 静态字段初始化表达式可引用前面单例/静态字段（声明序）。

## 三、边界 / E2 接口

- 单例不能实现协议/继承/泛型/手动 `instance`/构造器/前向引用：parser/sema
  负责（BND-07 已 PASS）；codegen 仅对 `new` 与 `instance` 赋值做兜底。
- 单例实例固定 GC 语义由 E5；本层 ARC 全局句柄进程常驻（可观察一致）。
- 静态字段可见性/@ReadOnly 等约束由 sema。

## 四、验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestS2SINGLE01' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
```
