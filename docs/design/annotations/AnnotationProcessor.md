# `AnnotationProcessor`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol AnnotationProcessor` |
| 包 | `xdk.annotations` |
| 稳定性 | `preview` |
| 依赖 | `AnnotationProcessorPhase`、`AnnotationProcessorContext`、`AnnotationProcessingResult`、`List`、`String` |

---

## 1. 定位

注解处理器的非泛型公共合同：稳定名称、声明支持的阶段、按阶段处理上下文并返回诊断/生成源码。

不做：不做运行时组件、不做处理器注册表、不做文件写入、不做网络、不做反射、不做增量缓存、不做依赖注入。

---

## 2. 设计逻辑

- XNull 禁止泛型协议；本协议不带类型参数。
- 处理器是**构建期插件**，由构建清单显式启用；不进入运行时，不由依赖包自动带入。
- `name()` 在同一个构建的处理器集合内唯一、稳定；用于诊断、缓存键和生成来源标注。
- `phases()` 返回非空、无重复的阶段列表；调度器只在这些阶段调用 `process`，并按 `Resolve → Validate → Generate → Finalize` 顺序调度。
- `process` 每次接收一个阶段上下文；同一处理器可能在不同阶段被多次调用，`Generate` 还可能多轮调用。
- 生成声明进入下一轮，直到没有新生成；处理器不得假设一轮完成，也不得在 `Finalize` 产生新声明。
- 处理器只读上下文中的元素；不得修改已有声明，只能通过返回的生成源码新增成员/类型/元数据。
- 生成必须确定性：相同输入、选项、编译器版本产生相同输出；不得依赖时间、随机数、绝对路径、哈希遍历顺序或网络。
- 用户错误用 `AnnotationDiagnostic` 表达，不抛异常；内部不变量破坏才允许 panic。
- 处理器不得直接写文件、访问网络、执行反射、加载类或启动进程；生成源码通过结果返回，由构建系统落盘。需要配置时使用 `AnnotationProcessorContext.options`，不得依赖隐式全局状态。
- 实现应无状态；如需缓存，必须自行同步，且缓存键包含输入哈希与选项。
- 协议无 close；处理器不持有需要释放的运行时资源。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `name()` 非空、单行、稳定；同一构建内唯一。
- `phases()` 非空、无重复、只含 `AnnotationProcessorPhase` 成员；返回列表是调用方无法修改内部状态的快照。
- `process` 返回非 null 结果；只处理上下文声明的阶段。
- `process` 不修改 `AnnotationProcessorContext` 或其元素。
- `process` 不产生半成品：要么不生成，要么返回完整源码；失败路径用 `Error` 诊断表达。
- 相同输入产生相同诊断顺序与相同生成源码内容。
- 不直接写文件、不联网、不反射；生成源码只通过结果返回；不依赖全局可变状态。
- 并发调用不产生数据竞争；实现要么无可变状态，要么内部同步。

---

## 4. 生命周期

实现由构建系统在构建期构造；一次构建内可被多个阶段/轮次调用；构建结束后丢弃；无 close；无运行时生命周期。

---

## 5. 构造契约

协议无构造。实现自行定义构造依赖；构造参数只能来自构建清单/显式配置，不得从全局单例隐式获取。

---

## 6. 字段表

无协议字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 处理器稳定名 | 无 | `String` | 无 |
| `phases` | 声明支持的阶段 | 无 | `List<AnnotationProcessorPhase>` | 无 |
| `process` | 执行一个阶段 | `AnnotationProcessorContext context` | `AnnotationProcessingResult` | 用户错误 → 结果中的诊断；内部不变量破坏 → panic |

说明：

- `name()` 不返回 null/空串；重复名称由调度器拒绝。
- `phases()` 不返回 null/空列表；重复阶段由调度器拒绝；顺序不作为语义。
- `process` 对未声明阶段不负责；调度器不得传入未声明阶段。若实现收到未声明阶段，属于合同错误，可 panic。
- `process` 对可恢复问题返回 `AnnotationProcessingResult`，不抛异常；`Error` 诊断使 `success()` 为 false。
- `process` 不返回 `Result`；结果对象已经承载诊断与生成物。
- 不提供 `close`/`reset`；需要跨轮状态时由实现自行管理并保证确定性/线程安全。
- 不提供 `dependsOn`/`options` 声明；依赖顺序和选项由构建清单管理。

---

## 8. 使用的技术

- 非泛型协议；
- 构建期插件；
- 阶段机；
- 固定点生成；
- 确定性输出；
- 诊断对象；
- 沙箱边界。

---

## 9. 需要的支撑

- 语言：protocol、String、List、class；
- 编译器/构建系统：处理器清单、阶段调度、轮次、生成源码落盘、增量缓存、沙箱；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

`AnnotationProcessorPhase`、`AnnotationProcessorContext`、`AnnotationProcessingResult`、`AnnotationDiagnostic`、`AnnotationElement`、`List`、`String`。

---

## 11. 所有权与并发

- 调用方持有协议引用；实现生命周期由构建系统管理。
- 实现必须可并发调用，或明确由调度器串行；协议不提供“非线程安全”标记，因此默认要求无共享可变状态。
- `process` 不保留上下文引用；不得把元素/选项缓存到运行时全局。
- 生成源码的所有权转移给返回结果；实现不得在返回后继续修改字符串或映射。
- 相等：协议无值语义；实现身份由具体类决定。

---

## 12. 示例与反例

正确：`DataProcessor` 在 `Validate` 检查 `@Data` 目标是否为类型，在 `Generate` 生成 `equals`/`toString`/`copy`，用 `Error` 诊断报告非法字段，用 `Warning` 诊断报告可选字段缺失；相同输入两次生成字节级一致。

正确：`RouteProcessor` 只声明 `Generate`，把路由表源码放入 `AnnotationProcessingResult.generatedSources()`，由构建系统写入生成目录。

反例：在 `process` 内写文件或联网；在运行时执行处理器；修改已有声明；用时间戳/随机数生成源码；依赖 `Map.keys()` 顺序输出；把用户错误抛成异常；返回 `null`；在 `Resolve` 生成源码；在 `Finalize` 继续生成新类型；把处理器自动带入依赖包。

---

## 13. 测试/场景义务

- `name()` 非空/稳定/重复拒绝；
- `phases()` 非空/无重复/快照；
- 调度器只调用声明阶段；
- `Generate` 多轮固定点；
- `Finalize` 后不再生成；
- 相同输入确定性输出；
- 诊断级别与 `success()`；
- 生成源码完整/非空/相对路径；
- 不写文件/不联网/不反射；
- 并发调用无数据竞争；
- 未声明阶段的合同错误；
- 运行时不存在处理器执行路径。

---

## 14. XNull 伪代码

```xnull
protocol AnnotationProcessor {
    String name();
    List<AnnotationProcessorPhase> phases();
    AnnotationProcessingResult process(AnnotationProcessorContext context);
}
```
