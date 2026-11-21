# `Http2SessionState`

| 项 | 值 |
| --- | --- |
| 类型 | `enum Http2SessionState` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

HTTP/2 会话状态：连接中、打开、关闭中、已关闭。

不做：流状态、TLS 状态、HTTP/1 状态。

---

## 2. 设计逻辑

- 简单枚举；只用于 `Http2Session.state()`。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Connecting` | 握手中 |
| `Open` | 可开流 |
| `Closing` | GOAWAY 中 |
| `Closed` | 已关闭 |

---

## 4. 生命周期

值类型；无 close。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `http2SessionStateName` | 稳定名 | `Http2SessionState state` | `String` | 无 |

---

## 8. 使用的技术

- 简单枚举；
- 名称映射。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源。

---

## 12. 示例与反例

正确：`session.state() == Http2SessionState.Open`。  
反例：把 `Closing` 当可开新流；用布尔值表达四态。

---

## 13. 测试/场景义务

四成员；名称；状态迁移。

---

## 14. XNull 伪代码

```xnull
enum Http2SessionState {
    Connecting,
    Open,
    Closing,
    Closed,
}

String http2SessionStateName(Http2SessionState state) {
    if state == Http2SessionState.Connecting { return "connecting" }
    if state == Http2SessionState.Open { return "open" }
    if state == Http2SessionState.Closing { return "closing" }
    return "closed"
}
```
