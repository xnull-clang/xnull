# `Http2Settings`

| 项 | 值 |
| --- | --- |
| 类型 | `class Http2Settings` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

HTTP/2 SETTINGS 值对象：头表、push、并发流、初始窗口、最大帧、最大头列表。

不做：SETTINGS 帧编解码、连接状态、流表、流量控制记账。

---

## 2. 设计逻辑

- 不可变；`with*` 返回新配置。
- 默认：headerTable 4096、enablePush false、maxConcurrentStreams 100、initialWindow 65535、maxFrame 16384、maxHeaderList 16384。
- 数值范围：maxFrame 16384..16777215；initialWindow 0..2147483647；计数 >0/≥0。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_headerTableSize` | `Int` | HPACK 表 |
| `_enablePush` | `Bool` | 服务端 push |
| `_maxConcurrentStreams` | `Int` | 并发流 |
| `_initialWindowSize` | `Int` | 初始窗口 |
| `_maxFrameSize` | `Int` | 最大帧 |
| `_maxHeaderListSize` | `Int` | 最大头列表 |

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Http2Settings()` | 无 | 默认 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `headerTableSize` / `withHeaderTableSize` | HPACK 表 | `Int` | `Int`/`Http2Settings` | 负值 → panic |
| `enablePush` / `withEnablePush` | push | `Bool` | `Bool`/`Http2Settings` | 无 |
| `maxConcurrentStreams` / `withMaxConcurrentStreams` | 并发流 | `Int` | `Int`/`Http2Settings` | ≤0 → panic |
| `initialWindowSize` / `withInitialWindowSize` | 初始窗口 | `Int` | `Int`/`Http2Settings` | 越界 → panic |
| `maxFrameSize` / `withMaxFrameSize` | 最大帧 | `Int` | `Int`/`Http2Settings` | 越界 → panic |
| `maxHeaderListSize` / `withMaxHeaderListSize` | 最大头列表 | `Int` | `Int`/`Http2Settings` | 负值 → panic |

---

## 8. 使用的技术

- 不可变配置；
- 协议常量范围。

---

## 9. 需要的支撑

- 语言：class、Int、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`new Http2Settings().withMaxConcurrentStreams(200)`。  
反例：maxFrame 1024；initialWindow 负数；修改实例期望变化。

---

## 13. 测试/场景义务

默认值；每个 with*；边界；非法；不可变。

---

## 14. XNull 伪代码

```xnull
class Http2Settings {
    final Int _headerTableSize
    final Bool _enablePush
    final Int _maxConcurrentStreams
    final Int _initialWindowSize
    final Int _maxFrameSize
    final Int _maxHeaderListSize

    Http2Settings() {
        _headerTableSize = 4096
        _enablePush = false
        _maxConcurrentStreams = 100
        _initialWindowSize = 65535
        _maxFrameSize = 16384
        _maxHeaderListSize = 16384
    }

    private Http2Settings(Int headerTableSize, Bool enablePush, Int maxConcurrentStreams,
                          Int initialWindowSize, Int maxFrameSize, Int maxHeaderListSize) {
        if headerTableSize < 0 || maxHeaderListSize < 0 {
            throw "Http2Settings: negative size"
        }
        if maxConcurrentStreams <= 0 { throw "Http2Settings: invalid streams" }
        if initialWindowSize < 0 || initialWindowSize > 2147483647 {
            throw "Http2Settings: invalid window"
        }
        if maxFrameSize < 16384 || maxFrameSize > 16777215 {
            throw "Http2Settings: invalid frame size"
        }
        _headerTableSize = headerTableSize
        _enablePush = enablePush
        _maxConcurrentStreams = maxConcurrentStreams
        _initialWindowSize = initialWindowSize
        _maxFrameSize = maxFrameSize
        _maxHeaderListSize = maxHeaderListSize
    }

    Int headerTableSize() { return _headerTableSize }
    Bool enablePush() { return _enablePush }
    Int maxConcurrentStreams() { return _maxConcurrentStreams }
    Int initialWindowSize() { return _initialWindowSize }
    Int maxFrameSize() { return _maxFrameSize }
    Int maxHeaderListSize() { return _maxHeaderListSize }

    Http2Settings withHeaderTableSize(Int value) {
        return new Http2Settings(value, _enablePush, _maxConcurrentStreams,
            _initialWindowSize, _maxFrameSize, _maxHeaderListSize)
    }

    Http2Settings withEnablePush(Bool value) {
        return new Http2Settings(_headerTableSize, value, _maxConcurrentStreams,
            _initialWindowSize, _maxFrameSize, _maxHeaderListSize)
    }

    Http2Settings withMaxConcurrentStreams(Int value) {
        return new Http2Settings(_headerTableSize, _enablePush, value,
            _initialWindowSize, _maxFrameSize, _maxHeaderListSize)
    }

    Http2Settings withInitialWindowSize(Int value) {
        return new Http2Settings(_headerTableSize, _enablePush, _maxConcurrentStreams,
            value, _maxFrameSize, _maxHeaderListSize)
    }

    Http2Settings withMaxFrameSize(Int value) {
        return new Http2Settings(_headerTableSize, _enablePush, _maxConcurrentStreams,
            _initialWindowSize, value, _maxHeaderListSize)
    }

    Http2Settings withMaxHeaderListSize(Int value) {
        return new Http2Settings(_headerTableSize, _enablePush, _maxConcurrentStreams,
            _initialWindowSize, _maxFrameSize, value)
    }
}
```
