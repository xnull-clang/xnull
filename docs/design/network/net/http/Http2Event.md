# `Http2Event`

| 项 | 值 |
| --- | --- |
| 类型 | `class Http2Event` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Http2EventKind`、`Http2ErrorCode`、`HttpHeaders`、`Bytes` |

---

## 1. 定位

HTTP/2 会话/流事件快照：类型、流 ID、头、数据、错误码、窗口增量。

不做：帧解析、流状态管理、自动响应。

---

## 2. 设计逻辑

- 字段按事件类型可空；`streamId` 0 表示连接级。
- 不可变；`data()` 返回副本；`headers()` 返回副本。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_kind` | `Http2EventKind` | 事件 |
| `_streamId` | `Int` | 流 ID/0 |
| `_headers` | `HttpHeaders?` | Headers |
| `_data` | `Bytes?` | Data |
| `_errorCode` | `Http2ErrorCode?` | Reset/GoAway/Error |
| `_windowSize` | `Int?` | WindowUpdate |

不变量：kind 非 null；streamId ≥0；不可变。

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Http2Event(kind, streamId, headers, data, errorCode, windowSize)` | 见字段 | kind 非 null；streamId ≥0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 类型 | 无 | `Http2EventKind` | 无 |
| `streamId` | 流 ID | 无 | `Int` | 无 |
| `headers` | 头副本 | 无 | `HttpHeaders?` | 无 |
| `data` | 数据副本 | 无 | `Bytes?` | 无 |
| `errorCode` | 错误码 | 无 | `Http2ErrorCode?` | 无 |
| `windowSize` | 窗口增量 | 无 | `Int?` | 无 |
| `isStreamEvent` | 是否流级 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 不可变事件；
- 可空字段；
- 副本。

---

## 9. 需要的支撑

- 语言：class、Int、Bool；
- 运行时：无；
- 接口：`Http2EventKind`、`Http2ErrorCode`、`HttpHeaders`、`Bytes`。

---

## 10. 依赖的特性/接口/类

`Http2EventKind`、`Http2ErrorCode`、`HttpHeaders`、`Bytes`。

---

## 11. 所有权与并发

不可变；头/数据副本；无资源。

---

## 12. 示例与反例

正确：`event.kind() == Http2EventKind.Data && event.streamId() == 3`。  
反例：把窗口更新当数据；修改 data 期望事件变化；流 ID 负数。

---

## 13. 测试/场景义务

各事件类型；可空字段；streamId 0；副本；isStreamEvent。

---

## 14. XNull 伪代码

```xnull
class Http2Event {
    final Http2EventKind _kind
    final Int _streamId
    final HttpHeaders? _headers
    final Bytes? _data
    final Http2ErrorCode? _errorCode
    final Int? _windowSize

    Http2Event(Http2EventKind kind, Int streamId, HttpHeaders? headers,
               Bytes? data, Http2ErrorCode? errorCode, Int? windowSize) {
        if kind == null { throw "Http2Event: null kind" }
        if streamId < 0 { throw "Http2Event: negative stream id" }
        _kind = kind
        _streamId = streamId
        if headers == null {
            _headers = null
        } else {
            _headers = headers.copy()
        }
        if data == null {
            _data = null
        } else {
            _data = data.copy()
        }
        _errorCode = errorCode
        _windowSize = windowSize
    }

    Http2EventKind kind() { return _kind }
    Int streamId() { return _streamId }
    HttpHeaders? headers() {
        if _headers == null { return null }
        return (_headers as HttpHeaders).copy()
    }
    Bytes? data() {
        if _data == null { return null }
        return (_data as Bytes).copy()
    }
    Http2ErrorCode? errorCode() { return _errorCode }
    Int? windowSize() { return _windowSize }
    Bool isStreamEvent() { return _streamId != 0 }
}
```

