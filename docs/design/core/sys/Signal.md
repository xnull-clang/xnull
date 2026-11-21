# `Signal`

| 项 | 值 |
| --- | --- |
| 类型 | `enum Signal` |
| 包 | `xdk.sys` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

跨平台信号标记：Hangup/Interrupt/Kill/Terminate/User1/User2。

不做：完整 POSIX 信号集、实时信号、handler 注册。

---

## 2. 设计逻辑

- 6 个成员；值语义。
- 信号号由 `signalNumber(Signal)` 映射；平台不支持 → `Unsupported`（调用方处理）。
- 不使用魔法整数。
- handler 注册为 X。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Hangup` | SIGHUP |
| `Interrupt` | SIGINT |
| `Kill` | SIGKILL |
| `Terminate` | SIGTERM |
| `User1` | SIGUSR1 |
| `User2` | SIGUSR2 |

不变量：成员固定；只允许追加。

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

## 7. 方法面

`Signal` 没有实例方法；`signalNumber(Signal)`、`Process.signal(Signal)` 使用该枚举。

---

## 8. 使用的技术

- 枚举；
- 平台信号号映射。

---

## 9. 需要的支撑

- 语言：enum、Int；
- 运行时/OS：信号常量；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；可共享；无资源。

---

## 12. 示例与反例

正确：`process.signal(Signal.Terminate)`。  
反例：用 9/15 魔法数；在不支持平台假装成功；用 Signal 做业务码。

---

## 13. 测试/场景义务

信号号映射；Process.signal；不支持平台；Kill 不可捕获。

---

## 14. XNull 伪代码

```xnull
enum Signal {
    Hangup,
    Interrupt,
    Kill,
    Terminate,
    User1,
    User2,
}

Int signalNumber(Signal signal) {
    if signal == Signal.Hangup { return 1 }
    if signal == Signal.Interrupt { return 2 }
    if signal == Signal.Kill { return 9 }
    if signal == Signal.Terminate { return 15 }
    if signal == Signal.User1 { return 10 }
    return 12
}
```
