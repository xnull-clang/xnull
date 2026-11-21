# `AnnotationDiagnosticSeverity`

| 项 | 值 |
| --- | --- |
| 类型 | `enum AnnotationDiagnosticSeverity` |
| 包 | `xdk.annotations` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

注解处理器诊断的严重级别：错误、警告、提示。构建调度器据此决定是否继续、是否判定 `AnnotationProcessingResult` 成功。

不做：不做日志级别，不做异常类型，不做退出码，不做诊断抑制策略。

---

## 2. 设计逻辑

- 三个级别固定：`Error`、`Warning`、`Note`。
- `Error` 表示构建必须失败；生成结果不得被当作有效产物。
- `Warning` 表示可疑但不阻止构建；仍计入诊断列表。
- `Note` 表示信息性说明；用于 IDE/文档/审计，不影响成功判定。
- 严重级别由处理器给出，构建系统不得把 `Error` 降级为 `Warning` 或忽略。
- 级别不携带诊断码；稳定码由 `AnnotationDiagnostic.code` 表达。
- 不做抑制；`@SuppressWarnings` 的抑制解析属于编译器诊断管线，不属于本枚举。

---

## 3. 表示与不变量

| 序号 | 成员 | 含义 | 对构建的影响 |
| --- | --- | --- | --- |
| 0 | `Error` | 不可恢复的注解/生成错误 | 失败；`success()` 为 false |
| 1 | `Warning` | 可疑但可继续 | 继续；`success()` 仍可为 true |
| 2 | `Note` | 信息性说明 | 不阻止；`success()` 仍可为 true |

不变量：成员固定为 3 项；序号稳定；值语义；可作 `Map` 键；`Error` 不得被静默忽略。

---

## 4. 生命周期

值类型；无 close；无资源；诊断创建后不可变；可跨任务共享。

---

## 5. 构造契约

枚举成员直接使用，无构造器。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

`AnnotationDiagnosticSeverity` 没有实例方法。

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| 无 | 枚举只提供成员 | 无 | 无 | 无 |

说明：

- `AnnotationProcessingResult.success()` 只检查 `Error`。
- `AnnotationDiagnostic.describe()` 负责把级别转成稳定文本；本枚举不提供格式化方法。

---

## 8. 使用的技术

- 简单枚举；
- 稳定序号；
- 构建期诊断分级。

---

## 9. 需要的支撑

- 语言：enum；
- 运行时：无；
- 接口：`AnnotationDiagnostic`、`AnnotationProcessingResult`。

---

## 10. 依赖的特性/接口/类

无。被 `AnnotationDiagnostic` 与 `AnnotationProcessingResult` 使用。

---

## 11. 所有权与并发

值语义；可跨任务共享；无同步需求；相等按枚举值。

---

## 12. 示例与反例

正确：未知注解产生 `Error`；重复的可选字段产生 `Warning`；生成来源说明产生 `Note`。

反例：把 `Warning` 当 `Error` 导致构建失败；把 `Error` 当 `Warning` 继续生成半成品；用日志级别替代诊断级别；把 `Note` 计入失败条件。

---

## 13. 测试/场景义务

- 3 个成员逐一存在；
- `success()` 对 Error/仅有 Warning/仅有 Note/混合级别的结果；
- 级别文本稳定；
- 诊断级别不被构建系统降级；
- 多个处理器的诊断合并后仍按最高严重级别判定。

---

## 14. XNull 伪代码

```xnull
enum AnnotationDiagnosticSeverity {
    Error,
    Warning,
    Note,
}
```
