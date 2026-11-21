# `WebSocketMessage`

| 项 | 值 |
| --- | --- |
| 类型 | `class WebSocketMessage` |
| 包 | `xdk.net.websocket` |
| 稳定性 | `preview` |
| 依赖 | `WebSocketMessageKind`、`WebSocketCloseCode`、`String`、`Bytes` |

---

## 1. 定位

收到的 WebSocket 消息快照：类型、文本、二进制、关闭码/原因。

不做：发送、分片、压缩、业务解码。

---

## 2. 设计逻辑

- 不可变字段 kind/text/binary/closeCode/closeReason；按类型可空。
- `text` 仅 Text；`binary` 仅 Binary；`closeCode`/`closeReason` 仅 Close。
- `data` 副本；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_kind` | `WebSocketMessageKind` | 类型 |
| `_text` | `String` | Text |
| `_binary` | `Bytes` | Binary |
| `_closeCode` | `WebSocketCloseCode?` | Close |
| `_closeReason` | `String` | Close |

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `WebSocketMessage(kind, text, binary, closeCode, closeReason)` | 见字段 | kind 非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 类型 | 无 | `WebSocketMessageKind` | 无 |
| `text` | 文本 | 无 | `String` | 无 |
| `binary` | 二进制副本 | 无 | `Bytes` | 无 |
| `closeCode` | 关闭码/无 | 无 | `WebSocketCloseCode?` | 无 |
| `closeReason` | 关闭原因 | 无 | `String` | 无 |
| `isText`/`isBinary`/`isPing`/`isPong`/`isClose` | 判定 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 可空字段。

---

## 9. 需要的支撑

- 语言：class、String、Bytes、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

`WebSocketMessageKind`、`WebSocketCloseCode`、`Bytes`。

---

## 11. 所有权与并发

不可变；副本；无资源。

---

## 12. 示例与反例

正确：`message.isClose()` 后读 `closeCode`。  
反例：Text 读 binary；Close 当错误；修改 binary 期望消息变化。

---

## 13. 测试/场景义务

Text/Binary/Ping/Pong/Close；空文本/空二进制；关闭码；副本；判定。

---

## 14. XNull 伪代码

```xnull
class WebSocketMessage {
    final WebSocketMessageKind _kind
    final String _text
    final Bytes _binary
    final WebSocketCloseCode? _closeCode
    final String _closeReason

    WebSocketMessage(WebSocketMessageKind kind, String text, Bytes binary,
                     WebSocketCloseCode? closeCode, String closeReason) {
        if kind == null { throw "WebSocketMessage: null kind" }
        _kind = kind
        _text = text
        _binary = binary
        _closeCode = closeCode
        _closeReason = closeReason
    }

    WebSocketMessageKind kind() { return _kind }
    String text() { return _text }
    Bytes binary() { return _binary }
    WebSocketCloseCode? closeCode() { return _closeCode }
    String closeReason() { return _closeReason }
    Bool isText() { return _kind == WebSocketMessageKind.Text }
    Bool isBinary() { return _kind == WebSocketMessageKind.Binary }
    Bool isPing() { return _kind == WebSocketMessageKind.Ping }
    Bool isPong() { return _kind == WebSocketMessageKind.Pong }
    Bool isClose() { return _kind == WebSocketMessageKind.Close }
}
```
