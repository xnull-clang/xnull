# `Http2EventKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum Http2EventKind` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

HTTP/2 会话/流事件类型：HEADERS、DATA、SETTINGS、PING、GOAWAY、WINDOW_UPDATE、RST_STREAM、ERROR。

不做：帧级编解码、HTTP/1 事件。

---

## 2. 设计逻辑

- 简单枚举；`Http2Event.kind()` 返回。
- `Error` 表示本地/传输错误事件，不是 HTTP 状态。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Headers` | 头帧 |
| `Data` | 数据帧 |
| `Settings` | 设置 |
| `Ping` | PING |
| `GoAway` | GOAWAY |
| `WindowUpdate` | 窗口更新 |
| `Reset` | RST_STREAM |
| `Error` | 错误 |

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
| `http2EventKindName` | 稳定名 | `Http2EventKind kind` | `String` | 无 |

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

正确：`event.kind() == Http2EventKind.Data`。  
反例：把 HEADERS 当完整请求；把 Error 当 HTTP 状态。

---

## 13. 测试/场景义务

八成员；名称；事件字段组合。

---

## 14. XNull 伪代码

```xnull
enum Http2EventKind {
    Headers,
    Data,
    Settings,
    Ping,
    GoAway,
    WindowUpdate,
    Reset,
    Error,
}

String http2EventKindName(Http2EventKind kind) {
    if kind == Http2EventKind.Headers { return "headers" }
    if kind == Http2EventKind.Data { return "data" }
    if kind == Http2EventKind.Settings { return "settings" }
    if kind == Http2EventKind.Ping { return "ping" }
    if kind == Http2EventKind.GoAway { return "goaway" }
    if kind == Http2EventKind.WindowUpdate { return "window_update" }
    if kind == Http2EventKind.Reset { return "reset" }
    return "error"
}
```
