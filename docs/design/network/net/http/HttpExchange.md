# `HttpExchange`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpExchange` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`HttpRequest`、`HttpResponse`、`ByteStream`、`SocketAddress`、`Error` |

---

## 1. 定位

服务端单次 HTTP 交换：读取请求、写响应、协议升级、关闭请求 body。

不做：路由、中间件、连接管理、HTTP/2 流。

---

## 2. 设计逻辑

- 字段 `_handle`、`_request`、`_remote`、`_local`、`_responded`、`_upgraded`、`_closed`。
- `respond` 与 `upgrade` 只能二选一；重复/冲突返回 `InvalidArgument`。
- `respond` 写完整响应；`upgrade` 发 101 并返回裸 `ByteStream`，HTTP 层停止读写。
- `close` 关闭交换/请求 body；幂等。
- 无全局状态；由 `HttpServer` 创建。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `HttpExchangeHandle` | 运行时交换 |
| `_request` | `HttpRequest` | 请求 |
| `_remote` | `SocketAddress` | 远端 |
| `_local` | `SocketAddress` | 本地 |
| `_responded` | `Bool` | 已响应 |
| `_upgraded` | `Bool` | 已升级 |
| `_closed` | `Bool` | 已关闭 |

不变量：responded/upgraded 互斥；closed 后不可响应；不可重复响应。

---

## 4. 生命周期

由服务器创建；必须 `respond` 或 `upgrade`，然后 `close`；close 幂等。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpExchange(...)` | 见 §6 | 非 null | null → panic |

主要供 `HttpServer` 使用。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `request` | 请求 | 无 | `HttpRequest` | 无 |
| `respond` | 写响应 | `HttpResponse response` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Io` |
| `respondStatus` | 空 body 响应 | `Int status` | `Result<Unit, Error>` | 同上 |
| `upgrade` | 协议升级 | `String protocol` | `Result<ByteStream, Error>` | `InvalidArgument`/`Unavailable`/`Io` |
| `isResponded` | 已响应 | 无 | `Bool` | 无 |
| `isUpgraded` | 已升级 | 无 | `Bool` | 无 |
| `remoteAddress` | 远端 | 无 | `SocketAddress` | 无 |
| `localAddress` | 本地 | 无 | `SocketAddress` | 无 |
| `close` | 关闭交换 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- 服务端交换；
- 101 upgrade；
- 单次响应状态机。

---

## 9. 需要的支撑

- 语言：class、Bool、Result；
- 运行时：`httpExchangeRespondRaw`、`httpExchangeUpgradeRaw`、`httpExchangeCloseRaw`、`HttpExchangeHandle`；
- 接口：`Context`、`HttpRequest`、`HttpResponse`、`ByteStream`、`SocketAddress`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`HttpRequest`、`HttpResponse`、`ByteStream`、`SocketAddress`、`Error`、`HttpExchangeHandle`、HTTP 运行时原语。

---

## 11. 所有权与并发

引用语义；由服务器持有；handler 使用；close 可并发；不可多线程同时响应。

---

## 12. 示例与反例

正确：`exchange.respond(HttpResponse.of(200).withBody(...))`。  
反例：respond 后再 upgrade；不响应直接返回；upgrade 后继续 HTTP 写；忘记 close。

---

## 13. 测试/场景义务

正常响应；状态响应；重复响应；respond/upgrade 冲突；upgrade 后裸流；close 幂等；未响应 500。

---

## 14. XNull 伪代码

```xnull
class HttpExchange {
    final HttpExchangeHandle _handle
    final HttpRequest _request
    final SocketAddress _remote
    final SocketAddress _local
    Bool _responded
    Bool _upgraded
    Bool _closed

    HttpExchange(HttpExchangeHandle handle, HttpRequest request,
                 SocketAddress remote, SocketAddress local) {
        if handle == null || request == null || remote == null || local == null {
            throw "HttpExchange: null argument"
        }
        _handle = handle
        _request = request
        _remote = remote
        _local = local
        _responded = false
        _upgraded = false
        _closed = false
    }

    HttpRequest request() { return _request }
    Bool isResponded() { return _responded }
    Bool isUpgraded() { return _upgraded }
    SocketAddress remoteAddress() { return _remote }
    SocketAddress localAddress() { return _local }

    Result<Unit, Error> respond(HttpResponse response) {
        if response == null { throw "HttpExchange.respond: null" }
        if _closed || _responded || _upgraded {
            return Err(new BasicError(ErrorKind.InvalidArgument, "exchange already used"))
        }
        Result<Unit, Error> written = httpExchangeRespondRaw(_handle, response)
        if written.isErr() { return Err(written.error()) }
        _responded = true
        return Ok(unit)
    }

    Result<Unit, Error> respondStatus(Int status) {
        return self.respond(HttpResponse.of(status))
    }

    Result<ByteStream, Error> upgrade(String protocol) {
        if protocol == null || protocol == "" {
            throw "HttpExchange.upgrade: empty protocol"
        }
        if _closed || _responded || _upgraded {
            return Err(new BasicError(ErrorKind.InvalidArgument, "exchange already used"))
        }
        Result<ByteStream, Error> upgraded = httpExchangeUpgradeRaw(_handle, protocol)
        if upgraded.isErr() { return Err(upgraded.error()) }
        _upgraded = true
        return upgraded
    }

    Result<Unit, Error> close() {
        if _closed { return Ok(unit) }
        _closed = true
        return httpExchangeCloseRaw(_handle)
    }
}
```

> `HttpExchangeHandle`、`httpExchange*Raw` 是运行时 HTTP 服务端原语；不是 XDK 公共类型。
