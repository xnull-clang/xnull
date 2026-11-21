# `TcpClient`

| 项 | 值 |
| --- | --- |
| 类型 | `class TcpClient` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SocketAddress`、`TcpStream`、`SocketOptions`、`Error` |

---

## 1. 定位

TCP 客户端角色：保存连接选项，提供地址/DNS 连接入口。

不做：重试策略、连接池、TLS、自动重连。

---

## 2. 设计逻辑

- 字段 `_options: SocketOptions`；构造复制。
- `connect` 委托 `TcpStream.connect`，返回流所有权。
- 无 close；客户端本身无资源；流由调用方 close。
- 可并发 connect。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_options` | `SocketOptions` | 连接选项 |

---

## 4. 生命周期

构造后复用；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TcpClient()` | 无 | 默认选项 | 无 |
| `TcpClient(SocketOptions options)` | options | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `connect` | 连接地址 | `Context, SocketAddress` | `Result<TcpStream, Error>` | `Network`/`Timeout`/`Cancelled` |
| `connect` | DNS + 连接 | `Context, String, Int` | `Result<TcpStream, Error>` | 同上 + `NotFound` |
| `options` | 选项副本 | 无 | `SocketOptions` | 无 |

---

## 8. 使用的技术

- 客户端连接封装；
- DNS + connect。

---

## 9. 需要的支撑

- 语言：class、String、Int、Result；
- 运行时：无（委托 TcpStream）；
- 接口：`Context`、`SocketAddress`、`TcpStream`、`SocketOptions`、`Error`。

---

## 10. 依赖的特性/接口/类

`Context`、`SocketAddress`、`TcpStream`、`SocketOptions`、`Error`。

---

## 11. 所有权与并发

引用语义；无资源；返回流归调用方；可并发。

---

## 12. 示例与反例

正确：`new TcpClient(options).connect(ctx, address)`。  
反例：期望客户端 close 关闭所有流；共享可变 options。

---

## 13. 测试/场景义务

地址/DNS 连接；选项；失败；取消；多连接；流所有权。

---

## 14. XNull 伪代码

```xnull
class TcpClient {
    final SocketOptions _options

    TcpClient() {
        _options = new SocketOptions()
    }

    TcpClient(SocketOptions options) {
        if options == null { throw "TcpClient: null options" }
        _options = options.copy()
    }

    Result<TcpStream, Error> connect(Context context, SocketAddress remote) {
        if context == null || remote == null {
            throw "TcpClient.connect: null argument"
        }
        return TcpStream.connect(context, remote, _options)
    }

    Result<TcpStream, Error> connect(Context context, String host, Int port) {
        if context == null { throw "TcpClient.connect: null context" }
        return TcpStream.connect(context, host, port, _options)
    }

    SocketOptions options() { return _options.copy() }
}
```
