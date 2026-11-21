# `Http2ErrorCode`

| 项 | 值 |
| --- | --- |
| 类型 | `enum Http2ErrorCode` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

HTTP/2 标准错误码：NO_ERROR、PROTOCOL_ERROR、INTERNAL_ERROR 等。

不做：自定义错误码、HTTP 状态码、业务错误。

---

## 2. 设计逻辑

- 简单枚举；码值由顶层 `http2ErrorCodeValue` 映射。
- 值语义；无 close。
- 自定义码用 `Http2Stream.reset` 的 Int 变体（X）。

---

## 3. 表示与不变量

| 成员 | 码 |
| --- | ---: |
| `NoError` | 0 |
| `ProtocolError` | 1 |
| `InternalError` | 2 |
| `FlowControlError` | 3 |
| `SettingsTimeout` | 4 |
| `StreamClosed` | 5 |
| `FrameSizeError` | 6 |
| `RefusedStream` | 7 |
| `Cancel` | 8 |
| `CompressionError` | 9 |
| `ConnectError` | 10 |
| `EnhanceYourCalm` | 11 |
| `InadequateSecurity` | 12 |
| `Http11Required` | 13 |

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
| `http2ErrorCodeValue` | 码值 | `Http2ErrorCode code` | `Int` | 无 |
| `http2ErrorCodeName` | 稳定名 | `Http2ErrorCode code` | `String` | 无 |

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

正确：`http2ErrorCodeValue(Http2ErrorCode.Cancel)` → 8。  
反例：把 HTTP 404 当 HTTP/2 错误码；自定义码塞进枚举。

---

## 13. 测试/场景义务

14 个码；码值；名称；只追加。

---

## 14. XNull 伪代码

```xnull
enum Http2ErrorCode {
    NoError,
    ProtocolError,
    InternalError,
    FlowControlError,
    SettingsTimeout,
    StreamClosed,
    FrameSizeError,
    RefusedStream,
    Cancel,
    CompressionError,
    ConnectError,
    EnhanceYourCalm,
    InadequateSecurity,
    Http11Required,
}

Int http2ErrorCodeValue(Http2ErrorCode code) {
    if code == Http2ErrorCode.NoError { return 0 }
    if code == Http2ErrorCode.ProtocolError { return 1 }
    if code == Http2ErrorCode.InternalError { return 2 }
    if code == Http2ErrorCode.FlowControlError { return 3 }
    if code == Http2ErrorCode.SettingsTimeout { return 4 }
    if code == Http2ErrorCode.StreamClosed { return 5 }
    if code == Http2ErrorCode.FrameSizeError { return 6 }
    if code == Http2ErrorCode.RefusedStream { return 7 }
    if code == Http2ErrorCode.Cancel { return 8 }
    if code == Http2ErrorCode.CompressionError { return 9 }
    if code == Http2ErrorCode.ConnectError { return 10 }
    if code == Http2ErrorCode.EnhanceYourCalm { return 11 }
    if code == Http2ErrorCode.InadequateSecurity { return 12 }
    return 13
}

String http2ErrorCodeName(Http2ErrorCode code) {
    if code == Http2ErrorCode.NoError { return "NO_ERROR" }
    if code == Http2ErrorCode.ProtocolError { return "PROTOCOL_ERROR" }
    if code == Http2ErrorCode.InternalError { return "INTERNAL_ERROR" }
    if code == Http2ErrorCode.FlowControlError { return "FLOW_CONTROL_ERROR" }
    if code == Http2ErrorCode.SettingsTimeout { return "SETTINGS_TIMEOUT" }
    if code == Http2ErrorCode.StreamClosed { return "STREAM_CLOSED" }
    if code == Http2ErrorCode.FrameSizeError { return "FRAME_SIZE_ERROR" }
    if code == Http2ErrorCode.RefusedStream { return "REFUSED_STREAM" }
    if code == Http2ErrorCode.Cancel { return "CANCEL" }
    if code == Http2ErrorCode.CompressionError { return "COMPRESSION_ERROR" }
    if code == Http2ErrorCode.ConnectError { return "CONNECT_ERROR" }
    if code == Http2ErrorCode.EnhanceYourCalm { return "ENHANCE_YOUR_CALM" }
    if code == Http2ErrorCode.InadequateSecurity { return "INADEQUATE_SECURITY" }
    return "HTTP_1_1_REQUIRED"
}
```
