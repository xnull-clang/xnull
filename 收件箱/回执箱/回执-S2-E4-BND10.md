# 回执：S2-E4 BND-10b（E5 bbeca42 之后的剩余缺口）

- 卡片：BND-10 补口（E5 已交 bbeca42；本卡只做剩余缺口）
- 提交：`a34a392`（仅 pod/e4-codegen，未 merge main）
- 结论：E5 已覆盖 GC/ARC 分配、scan、所有权守卫、退出收集；本卡补
  **全局根**（数据枚举项/单例实例/单例 GC 静态字段）与 GC 单例/数据枚举分配。
  @arc/stack 分配路径核对为 **NO-GAP**（stack 候选按 ARC 分配，栈优化未启用）。

## 一、核对 main（合并 E5 后）

- `classes.go` 已不再恒 `rt_arc_new`：`isGC` 类 `rt_gc_new` + scan；非环/stack 候选
  `rt_arc_new`。E5 实现在 main（96a6942）内，不重复。
- E5 边界：无全局根登记、无 stack 分配、无中途收集。本卡处理全局根。

## 二、红 → 绿

| 用例 | 修前（红） | 修后（绿） |
|---|---|---|
| 数据枚举项 `Status.Ready` | 仍 `rt_arc_new`；退出 `rt_gc_collect` 无根可依 | `rt_gc_new` + `rt_gc_root_add(xn_enum_Status_Ready)` |
| 单例 `AppInfo.instance` | `rt_arc_new`（未按 §9.3 固定 GC） | `rt_gc_new` + `rt_gc_root_add(xn_single_AppInfo)` |
| 单例静态字段为 GC 类型 | 无根登记 | 初始化后 `rt_gc_root_add`；赋值时 remove/add |
| `@arc`/stack 候选类 | — | 保持 `rt_arc_new`（身份不变，栈优化未启用=NO-GAP） |
| 混合图 GC 字段 | E5 已有 scan | 保持；单例/枚举作为根使其持有的 GC 可达 |

回归：`go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1` 全绿。

## 三、实现要点

- `enum.go`：`collectDataEnum` 标记 `isGC`；项构造走 `rt_gc_new`；
  `xn_init_enums` 每项 `rt_gc_root_add`（GC 全局根）。
- `singleton.go`：单例 `isGC=true`；实例 `rt_gc_new` + `rt_gc_root_add`；
  静态字段为 GC 类型时登记根。
- `singletonStatic` 赋值路径：GC 字段 `rt_gc_root_remove → 赋值 → 条件 add`。
- `classes_expr.go`：`isGCTypeC` 覆盖类/数据枚举/单例（供根与所有权判断）。
- 未改动 E5 的 GC/ARC 分配、scan、退出收集与所有权守卫。

## 四、边界 / E5 接口

- 中途安全点/收集中间态仍归 E5；本卡只保证进程生命周期根（启动登记）。
- 容器元素 GC 仍显式拒绝（E5/B2）；容器中介环归 E2。
- stack 优化（§2.7 许可）未启用；StackEligible 按 ARC 分配，行为与 E5 一致。
- E5 旧测试 `TestS2MEM01StructNotInARCGC` 假设 struct 未实现；本分支已合入
  STRUCT-01，更新为「struct 值类型可发射但不得进入 ARC/GC」断言。

## 五、验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestBND10b|TestBND10' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
```
