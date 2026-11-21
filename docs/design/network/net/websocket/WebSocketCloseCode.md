# `WebSocketCloseCode`

| 项 | 值 |
| --- | --- |
| 类型 | `enum WebSocketCloseCode` |
| 包 | `xdk.net.websocket` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

WebSocket 标准关闭码：Normal/GoingAway/ProtocolError 等。

不做：自定义码（`closeWithCode` X）、HTTP 状态。

---

## 2. 设计逻辑

- 简单枚举；码值由顶层函数映射。
- 正常关闭不是 `Err`。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 码 |
| --- | ---: |
| `Normal` | 1000 |
| `GoingAway` | 1001 |
| `ProtocolError` | 1002 |
| `UnsupportedData` | 1003 |
| `NoStatus` | 1005 |
| `Abnormal` | 1006 |
| `InvalidPayload` | 1007 |
| `PolicyViolation` | 1008 |
| `MessageTooBig` | 1009 |
| `MandatoryExtension` | 1010 |
| `InternalError` | 1011 |
| `TlsHandshake` | 1015 |

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
| `webSocketCloseCodeValue` | 码 | `WebSocketCloseCode code` | `Int` | 无 |
| `webSocketCloseCodeName` | 名称 | `WebSocketCloseCode code` | `String` | 无 |

---

## 8. 使用的技术

- 简单枚举；
- 码表。

---

## 9. 需要的支撑

- 语言：enum、Int、String；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源。

---

## 12. 示例与反例

正确：`webSocketCloseCodeValue(WebSocketCloseCode.Normal)` → 1000。  
反例：把 1006 当可发送关闭码；自定义码塞进枚举。

---

## 13. 测试/场景义务

码值；名称；1005/1006/1015 保留语义；只追加。

---

## 14. XNull 伪代码

```xnull
enum WebSocketCloseCode {
    Normal,
    GoingAway,
    ProtocolError,
    UnsupportedData,
    NoStatus,
    Abnormal,
    InvalidPayload,
    PolicyViolation,
    MessageTooBig,
    MandatoryExtension,
    InternalError,
    TlsHandshake,
}

Int webSocketCloseCodeValue(WebSocketCloseCode code) {
    if code == WebSocketCloseCode.Normal { return 1000 }
    if code == WebSocketCloseCode.GoingAway { return 1001 }
    if code == WebSocketCloseCode.ProtocolError { return 1002 }
    if code == WebSocketCloseCode.UnsupportedData { return 1003 }
    if code == WebSocketCloseCode.NoStatus { return 1005 }
    if code == WebSocketCloseCode.Abnormal { return 1006 }
    if code == WebSocketCloseCode.InvalidPayload { return 1007 }
    if code == WebSocketCloseCode.PolicyViolation { return 1008 }
    if code == WebSocketCloseCode.MessageTooBig { return 1009 }
    if code == WebSocketCloseCode.MandatoryExtension { return 1010 }
    if code == WebSocketCloseCode.InternalError { return 1011 }
    return 1015
}

String webSocketCloseCodeName(WebSocketCloseCode code) {
    if code == WebSocketCloseCode.Normal { return "normal" }
    if code == WebSocketCloseCode.GoingAway { return "going_away" }
    if code == WebSocketCloseCode.ProtocolError { return "protocol_error" }
    if code == WebSocketCloseCode.UnsupportedData { return "unsupported_data" }
    if code == WebSocketCloseCode.NoStatus { return "no_status" }
    if code == WebSocketCloseCode.Abnormal { return "abnormal" }
    if code == WebSocketCloseCode.InvalidPayload { return "invalid_payload" }
    if code == WebSocketCloseCode.PolicyViolation { return "policy_violation" }
    if code == WebSocketCloseCode.MessageTooBig { return "message_too_big" }
    if code == WebSocketCloseCode.MandatoryExtension { return "mandatory_extension" }
    if code == WebSocketCloseCode.InternalError { return "internal_error" }
    return "tls_handshake"
}
```
