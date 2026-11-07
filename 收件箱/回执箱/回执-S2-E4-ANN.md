# 回执：S2-E4 ANN-01 codegen 面

- 卡片：ANN-01（注解声明/使用发射、`@Override` 无运行期开销）
- 提交：`eebd8a0`（仅 pod/e4-codegen，未 merge main；按纪律）
- 范围：codegen 零运行期开销；未知/重复注解由 sema 拒（与 E2 对齐）。

## 一、红 → 绿

| 用例 | 修前（红） | 修后（绿） |
|---|---|---|
| `@annotation Marker { final String tag; final Int level }` + 类/字段/方法/入口使用 | `codegen：顶层声明 *xfront.AnnotationDecl 未支持` | 程序正常运行；产物无注解元数据 |
| `@Override` 实现协议方法 | 同源（含注解声明时） | vtable 正常，产物无 `Override` |
| 零开销判据 | — | 带注解程序与等价无注解程序生成的 C **逐字节一致** |
| 未知注解 | — | codegen 中性（不发射、不崩溃）；接受/拒绝由 sema 负责 |

回归：`go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1` 全绿。

## 二、实现要点

- `EmitC` 首遍声明分派跳过 `*xfront.AnnotationDecl`：注解声明不产生 C 结构/
  函数/全局/布局。
- 注解使用（`Annos`）与 `@Override` 仅作为 AST 元数据：codegen 不读取、不发射，
  因此无运行期开销。
- 注解字段/参数值不参与常量表或初始化；不分配对象。
- 未知/重复注解：sema 判定（不在 codegen 跨域）；codegen 保持中性，不生成坏 C。

## 三、边界 / E2 接口

- `@annotation` 字段类型/常量初始化式、目标限制、未知/重复注解诊断由 sema
  负责；codegen 只保证零发射。
- `@Override` 与协议对应关系由 sema（BND-05 已 PASS）；codegen 不重复校验。
- 注解参数不进 ABI/反射（语言无运行期反射面）。

## 四、验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestS2ANN01' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
```
