# `Http2StreamState`

| 项 | 值 |
| --- | --- |
| 类型 | `enum Http2StreamState` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

HTTP/2 流状态：idle/open/half-closed/closed/reserved。

不做：流表调度、HTTP/1 连接状态。

---

## 2. 设计逻辑

- 简单枚举，覆盖 HTTP/2 流的可观察状态。
- `Http2Stream.state()` 返回；状态迁移由运行时保证。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Idle` | 未使用 |
| `Open` | 双向打开 |
| `HalfClosedLocal` | 本地已结束 |
| `HalfClosedRemote` | 远端已结束 |
| `Closed` | 已关闭 |
| `ReservedLocal` | 本地 reserved |
| `ReservedRemote` | 远端 reserved |

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
| `http2StreamStateName` | 稳定名 | `Http2StreamState state` | `String` | 无 |

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

正确：`stream.state() == Http2StreamState.HalfClosedLocal`。  
反例：把 reserved 当可发送 data；用布尔值表达多态。

---

## 13. 测试/场景义务

七成员；名称；状态迁移边界。

---

## 14. XNull 伪代码

```xnull
enum Http2StreamState {
    Idle,
    Open,
    HalfClosedLocal,
    HalfClosedRemote,
    Closed,
    ReservedLocal,
    ReservedRemote,
}

String http2StreamStateName(Http2StreamState state) {
    if state == Http2StreamState.Idle { return "idle" }
    if state == Http2StreamState.Open { return "open" }
    if state == Http2StreamState.HalfClosedLocal { return "half_closed_local" }
    if state == Http2StreamState.HalfClosedRemote { return "half_closed_remote" }
    if state == Http2StreamState.Closed { return "closed" }
    if state == Http2StreamState.ReservedLocal { return "reserved_local" }
    return "reserved_remote"
}
```
