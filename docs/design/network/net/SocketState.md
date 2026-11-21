# `SocketState`

| 项 | 值 |
| --- | --- |
| 类型 | `enum SocketState` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

TCP/UDP socket 状态：打开、只关读、只关写、完全关闭。

不做：TLS 状态、HTTP 状态、连接池状态。

---

## 2. 设计逻辑

- 简单枚举；`TcpStream.state()` 返回细分状态，`UdpSocket.state()` 只使用 `Open`/`Closed`。
- `ShutdownMode.Read` → `ReadClosed`；`Write` → `WriteClosed`；`Both` → `Closed`。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Open` | 读写均打开 |
| `ReadClosed` | 读方向关闭 |
| `WriteClosed` | 写方向关闭 |
| `Closed` | 完全关闭 |

---

## 4. 生命周期

值类型；无 close；可共享。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

无实例方法。顶层函数：

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `socketStateName` | 稳定名 | `SocketState state` | `String` | 无 |

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

值语义；无资源；可共享。

---

## 12. 示例与反例

正确：`stream.state() == SocketState.ReadClosed`。  
反例：把 `Closed` 当可继续写；用布尔值表达三种状态。

---

## 13. 测试/场景义务

四个成员；shutdown 映射；UDP 只用 Open/Closed；名称。

---

## 14. XNull 伪代码

```xnull
enum SocketState {
    Open,
    ReadClosed,
    WriteClosed,
    Closed,
}

String socketStateName(SocketState state) {
    if state == SocketState.Open { return "open" }
    if state == SocketState.ReadClosed { return "read_closed" }
    if state == SocketState.WriteClosed { return "write_closed" }
    return "closed"
}
```
