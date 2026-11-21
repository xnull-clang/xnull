# `Error`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Error` |
| 包 | `xdk.errors` |
| 稳定性 | `stable` |
| 依赖 | `ErrorKind` |

---

## 1. 定位

所有错误类型的最小公共面。只包含 `kind()` 与 `describe()`。

不做：code/details/causes、日志、重试、异常栈。

---

## 2. 设计逻辑

- 任何错误都必须能被统一观测，所以只保留最小两方法。
- 结构化信息放 `DetailedError` 或具体类；不污染基础协议。
- 只有 `class` 可以实现；`cause` 不是协议成员。

---

## 3. 使用的技术

- 非泛型协议；
- 单行诊断文本；
- 值类型 `ErrorKind`。

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
| `kind` | 返回失败分类 | 无 | `ErrorKind` | 无 |
| `describe` | 返回单行诊断 | 无 | `String` | 无 |

契约：

- `kind()` 生命周期内不变。
- `describe()` 单行、稳定、无换行/制表/控制字符。
- 不包含结构化 details；不包含敏感信息。

---

## 7. XNull 伪代码

```xnull
protocol Error {
    ErrorKind kind();
    String describe();
}
```
