# `ConnectionPool`

| 项 | 值 |
| --- | --- |
| 类型 | `class ConnectionPool` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`ByteStream`、`PoolKey`、`PooledConnection`、`ConnectionPoolOptions`、`ConnectionPoolStats`、`Error` |

---

## 1. 定位

显式连接池：按 `PoolKey` 借出/归还 `ByteStream`，控制总上限、每键上限、空闲/寿命、等待超时。

不做：TLS 握手、HTTP 语义、全局池、健康检查协议、连接迁移。

---

## 2. 设计逻辑

- 字段 `_handle`、`_options`、`_open`；connector 由构造参数提供。
- 池只管理 `ByteStream`；TCP/TLS 连接由 connector 创建。
- `acquire` 优先复用空闲连接；没有则按上限创建；达到上限等待或 `Timeout`。
- `release` 归还；超过空闲/寿命/健康检查失败的连接由池关闭。
- `close` 幂等；关闭空闲连接；已借出连接在 release 时关闭。
- 无全局池；每个池独立；可并发 acquire/release。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `ConnectionPoolHandle` | 运行时池句柄 |
| `_options` | `ConnectionPoolOptions` | 配置副本 |
| `_open` | `Bool` | 是否可用 |

不变量：handle/options 非 null；close 后 open=false。

---

## 4. 生命周期

构造创建；必须 close；close 幂等；关闭后 acquire `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ConnectionPool(ConnectionPoolOptions options, Result<ByteStream, Error>(Context, PoolKey) connector)` | options/connector | 非 null | 创建失败 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `acquire` | 借出连接 | `Context context, PoolKey key` | `Result<PooledConnection, Error>` | `Timeout`/`Cancelled`/`Unavailable`/`Network` |
| `release` | 归还连接 | `PooledConnection connection` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable` |
| `stats` | 统计快照 | 无 | `ConnectionPoolStats` | 无 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |
| `close` | 关闭池 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- 显式连接池；
- 空闲/寿命/健康检查；
- 等待超时；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Bool、Result、函数类型；
- 运行时：`connectionPoolCreateRaw`、`connectionPoolAcquireRaw`、`connectionPoolReleaseRaw`、`connectionPoolStatsRaw`、`connectionPoolCloseRaw`、`ConnectionPoolHandle`；
- 接口：`Context`、`ByteStream`、`PoolKey`、`PooledConnection`、`ConnectionPoolOptions`、`ConnectionPoolStats`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`ByteStream`、`PoolKey`、`PooledConnection`、`ConnectionPoolOptions`、`ConnectionPoolStats`、`Error`、`ConnectionPoolHandle`、池运行时原语。

---

## 11. 所有权与并发

引用语义；拥有池；借出连接归调用方临时使用；release 归还；可并发；close 可并发。

---

## 12. 示例与反例

正确：`pool.acquire(ctx,key)` → 使用 → `pool.release(conn)`。  
反例：release 后继续用；重复 release；把池当全局单例；acquire 不处理 Timeout。

---

## 13. 测试/场景义务

复用/新建；上限；每键限制；等待/超时/取消；空闲/寿命；健康检查；release；close 幂等；关闭后 acquire；stats。

---

## 14. XNull 伪代码

```xnull
class ConnectionPool {
    final ConnectionPoolHandle _handle
    final ConnectionPoolOptions _options
    Bool _open

    ConnectionPool(ConnectionPoolOptions options,
                   Result<ByteStream, Error>(Context, PoolKey) connector) {
        if options == null || connector == null {
            throw "ConnectionPool: null argument"
        }
        Result<ConnectionPoolHandle, Error> raw = connectionPoolCreateRaw(options, connector)
        if raw.isErr() {
            throw "ConnectionPool: create failed: " + raw.error().describe()
        }
        _handle = raw.value()
        _options = options.copy()
        _open = true
    }

    Result<PooledConnection, Error> acquire(Context context, PoolKey key) {
        if context == null || key == null {
            throw "ConnectionPool.acquire: null argument"
        }
        if !_open { return Err(unavailableError("connection pool")) }
        return connectionPoolAcquireRaw(_handle, context, key)
    }

    Result<Unit, Error> release(PooledConnection connection) {
        if connection == null { throw "ConnectionPool.release: null" }
        if !_open { return Err(unavailableError("connection pool")) }
        return connectionPoolReleaseRaw(_handle, connection)
    }

    ConnectionPoolStats stats() { return connectionPoolStatsRaw(_handle) }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return connectionPoolCloseRaw(_handle)
    }
}
```

> `ConnectionPoolHandle`、`connectionPool*Raw` 是运行时连接池原语；不是 XDK 公共类型。
