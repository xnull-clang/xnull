# `Formatter`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Formatter` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | `LogRecord` |

---

## 1. 定位

日志记录→单行文本的协议。

不做：输出、过滤、脱敏、JSON（X）。

---

## 2. 设计逻辑

- 最小面：`format(record) -> String`。
- 必须返回单行；不含换行/控制字符。
- 不修改 record；不持有 record 引用。
- 无状态或不可变；线程安全由实现声明。

---

## 3. 表示与不变量

协议无字段。

---

## 4. 生命周期

协议无构造；实现决定。

---

## 5. 构造契约

协议无构造。

---

## 6. 字段表

无。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `format` | 格式化 | `LogRecord record` | `String` | null → panic |

---

## 8. 使用的技术

- 非泛型协议；
- 文本格式化。

---

## 9. 需要的支撑

- 语言：protocol、String；
- 运行时：无；
- 接口：`LogRecord`。

---

## 10. 依赖的特性/接口/类

`LogRecord`。

---

## 11. 所有权与并发

无状态/不可变；可共享。

---

## 12. 示例与反例

正确：TextFormatter。  
反例：输出多行；修改 record；持有 record。

---

## 13. 测试/场景义务

单行；字段；级别；null；并发声明。

---

## 14. XNull 伪代码

```xnull
protocol Formatter {
    String format(LogRecord record);
}
```
