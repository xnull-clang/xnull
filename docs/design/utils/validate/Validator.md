# `Validator`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Validator` |
| 包 | `xdk.validate` |
| 稳定性 | `preview` |
| 依赖 | `JsonValue`、`ValidationContext` |

---

## 1. 定位

非泛型校验协议：接收 `JsonValue` 与上下文，把错误写入上下文。

不做：返回值、错误抛出、异步、资源生命周期、消息格式化。

---

## 2. 设计逻辑

- 固定 `JsonValue`，避免 XNull 泛型协议限制。
- `value == null` 表示字段缺失；validator 必须自行决定缺失是否合法。
- 无效数据通过 `context.addError` 报告，不抛业务异常。
- `describe` 用于调试/文档，不参与判定。
- 实现应只读 value；不得修改 JsonValue/JsonObject。
- 可组合：`Rule`、`Schema` 都实现本协议。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `validate` 不返回错误值；错误只进入 context；
- 不因普通无效数据抛异常；
- `describe` 非 null；
- 同一 validator 可复用；调用不保留可变状态（除非实现明确声明）。

---

## 4. 生命周期

实现决定；无 close；无资源。

---

## 5. 构造契约

协议无构造；由实现定义。

---

## 6. 字段表

无协议字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `validate` | 校验 | `JsonValue value, ValidationContext context` | `void` | null context → panic |
| `describe` | 描述 | 无 | `String` | 无 |

说明：

- `value` 可为 null，表示缺失。
- `context` 为 null 是合同错误。
- 实现可在 `failFast` 生效后提前返回；应检查 `context.isStopped()`。

---

## 8. 使用的技术

- 非泛型协议；
- 上下文写入；
- 组合模式；
- 只读输入。

---

## 9. 需要的支撑

- 语言：protocol、String、JsonValue；
- 运行时：无；
- 接口：`JsonValue`、`ValidationContext`。

---

## 10. 依赖的特性/接口/类

`JsonValue`、`ValidationContext`。

---

## 11. 所有权与并发

协议引用；实现可共享；context 由调用方持有且非线程安全；无资源。

---

## 12. 示例与反例

正确：`Validator v = Rules.string()`；`v.validate(value, context)`。  
反例：validate 返回 Bool 当唯一结果；无效数据抛异常；修改 value；忽略 failFast。

---

## 13. 测试/场景义务

Rule/Schema 实现；null value；缺失字段；错误路径；describe；failFast；组合。

---

## 14. XNull 伪代码

```xnull
protocol Validator {
    void validate(JsonValue value, ValidationContext context)
    String describe()
}
```
