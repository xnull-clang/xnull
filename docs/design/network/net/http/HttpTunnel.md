# `HttpTunnel`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpTunnel` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`ByteStream`、`SocketAddress`、`HttpProxyConfig`、`Error` |

---

## 1. 定位

HTTP CONNECT 隧道：通过代理连接目标，返回裸字节流。

不做：TLS 握手、HTTP 请求转发、SOCKS。

---

## 2. 设计逻辑

- 无状态；构造器私有；静态 `connect`。
- 成功返回隧道流，拥有 transport；失败时调用方关闭 transport。
- Context 取消；代理认证/超时错误传播。
- 无 close；返回的流需 close。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

静态方法；返回流所有权转移。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpTunnel()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `connect` | 建隧道 | `Context, ByteStream transport, SocketAddress target, HttpProxyConfig config` | `Result<ByteStream, Error>` | `Network`/`PermissionDenied`/`Timeout`/`Cancelled`/`DataCorrupted` |

---

## 8. 使用的技术

- HTTP CONNECT；
- 隧道流；
- 所有权转移。

---

## 9. 需要的支撑

- 语言：class、Result；
- 运行时：`httpTunnelConnectRaw`；
- 接口：`Context`、`ByteStream`、`SocketAddress`、`HttpProxyConfig`、`Error`。

---

## 10. 依赖的特性/接口/类

`Context`、`ByteStream`、`SocketAddress`、`HttpProxyConfig`、`Error`、`httpTunnelConnectRaw`。

---

## 11. 所有权与并发

成功后拥有 transport；失败调用方关闭；可并发不同 transport。

---

## 12. 示例与反例

正确：`HttpTunnel.connect(ctx,tcp,target,config)`。  
反例：失败后让 tunnel 关闭 transport；成功后再关闭 transport；用 CONNECT 做普通转发。

---

## 13. 测试/场景义务

成功/失败；认证；超时/取消；目标地址；transport 所有权；TLS 组合。

---

## 14. XNull 伪代码

```xnull
class HttpTunnel {
    private HttpTunnel() {
    }

    static Result<ByteStream, Error> connect(Context context, ByteStream transport,
                                             SocketAddress target, HttpProxyConfig config) {
        if context == null || transport == null || target == null || config == null {
            throw "HttpTunnel.connect: null argument"
        }
        return httpTunnelConnectRaw(context, transport, target, config)
    }
}
```

> `httpTunnelConnectRaw` 是运行时 CONNECT 原语；不是 XDK 公共类型。
