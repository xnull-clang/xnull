# `ValueParser`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol ValueParser` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `Error` |

---

## 1. 定位

选项值解析/归一化协议：把用户输入的字符串校验并转换为规范字符串。

不做：类型化对象、全局注册、默认值、必填判断、I/O。

---

## 2. 设计逻辑

- 协议只有 `typeName` 与 `parse`。
- `parse` 返回规范字符串而不是泛型对象，避免泛型协议；应用仍需自己做最终类型转换。
- 失败统一 `InvalidArgument`，消息单行；`Parser` 会把它包装成 `UsageError`。
- 实现必须无副作用、可重复调用、可共享。
- 协议不持有状态；需要配置的 parser 由实现类字段保存。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- 不修改输入字符串；
- 不返回 null；
- 失败不写终端/日志；
- 同一输入在生命周期内结果稳定；
- `typeName` 非空且单行。

---

## 4. 生命周期

协议无构造；实现决定。无 close 要求。

---

## 5. 构造契约

协议无构造。

---

## 6. 字段表

无协议字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `typeName` | 值类型名（help/错误） | 无 | `String` | 无 |
| `parse` | 校验/归一化 | `String text` | `Result<String, Error>` | `InvalidArgument` |

契约：

- `parse` 收到空串也必须显式接受或拒绝，不得把空串当“缺失”。
- 返回的字符串应为规范形式，便于后续 `parseInt`/`parseBool` 等转换。
- `typeName` 用于错误消息，例如 `"port"`、`"duration"`。

---

## 8. 使用的技术

- 非泛型协议；
- 字符串校验；
- Result。

---

## 9. 需要的支撑

- 语言：protocol、String、Result；
- 运行时：无；
- 接口：`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

无状态实现可共享；有状态实现由调用方声明并发；`parse` 不应修改共享状态。

---

## 12. 示例与反例

正确：端口 parser 接受 `"1"`..`"65535"`，返回规范十进制字符串。  
反例：返回 `Int` 需要泛型协议；失败时写 stderr；把 `null`/空串当合法值而不声明。

---

## 13. 测试/场景义务

合法/非法值；空串；前后空白；边界；错误消息；重复调用稳定性；`typeName` 非空。

---

## 14. XNull 伪代码

```xnull
protocol ValueParser {
    String typeName();
    Result<String, Error> parse(String text);
}
```
