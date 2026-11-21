# `DetailedError`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol DetailedError` |
| 包 | `xdk.errors` |
| 稳定性 | `stable` |
| 依赖 | `ErrorKind` |

---

## 1. 定位

需要 `message`/`code` 的错误扩展协议。

不做：details/causes（列表返回不放进最小协议）、日志、重试。

---

## 2. 设计逻辑

- 独立协议，不继承 `Error`；实现类同时声明 `implements Error, DetailedError`。
- 避免协议继承带来的类型/实现问题。
- `message`/`code` 是报告、日志、边界映射的稳定字段。

---

## 3. 使用的技术

- 非泛型协议；
- 稳定错误码字符串；
- 单行诊断格式。

---

## 4. 需要的支撑

- 语言：protocol、class、String、ErrorKind；
- 运行时：无；
- 接口：无。

---

## 5. 依赖的特性/接口/类

`ErrorKind`。

---

## 6. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 分类 | 无 | `ErrorKind` | 无 |
| `describe` | 单行诊断 | 无 | `String` | 无 |
| `message` | 消息 | 无 | `String` | 无 |
| `code` | 稳定码 | 无 | `String` | 无 |

契约：

- `message()` 非空、单行、无控制字符。
- `code()` 为空串或 `[a-z0-9_.-]+`。
- `describe()` 固定格式：`[code] KindName: message` 或 `KindName: message`。
- `kind`/`message`/`code` 生命周期内不变。

---

## 7. XNull 伪代码

```xnull
protocol DetailedError {
    ErrorKind kind();
    String describe();
    String message();
    String code();
}
```
