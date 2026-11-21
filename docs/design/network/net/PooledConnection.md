# `PooledConnection`

| 项 | 值 |
| --- | --- |
| 类型 | `class PooledConnection` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `ByteStream`、`PoolKey` |

---

## 1. 定位

连接池借出的连接视图：底层流、池键、是否复用、创建时间、年龄。

不做：自动释放、重连、TLS 握手、健康检查。

---

## 2. 设计逻辑

- 字段 `_stream`、`_key`、`_reused`、`_createdMonoMillis`。
- 由 `ConnectionPool.acquire` 创建；归调用方临时使用，`release` 交回池。
- `stream()` 借用底层流；不转移所有权。
- `ageMillis(nowMono)` 用于池的空闲/寿命判断。
- 无 close；连接释放由 `ConnectionPool.release` 完成。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_stream` | `ByteStream` | 底层流 |
| `_key` | `PoolKey` | 池键 |
| `_reused` | `Bool` | 是否复用 |
| `_createdMonoMillis` | `Long` | 创建单调时间 |

不变量：stream/key 非 null；created ≥0；不可变视图。

---

## 4. 生命周期

`acquire` 创建；使用后 `release`；无自身 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `PooledConnection(ByteStream stream, PoolKey key, Bool reused, Long createdMonoMillis)` | 见字段 | 非 null；created ≥0 | 非法 → panic |

主要供 `ConnectionPool` 使用。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `stream` | 底层流 | 无 | `ByteStream` | 无 |
| `key` | 池键 | 无 | `PoolKey` | 无 |
| `isReused` | 是否复用 | 无 | `Bool` | 无 |
| `createdMonoMillis` | 创建时间 | 无 | `Long` | 无 |
| `ageMillis` | 年龄 | `Long nowMonoMillis` | `Long` | 无 |

---

## 8. 使用的技术

- 连接视图；
- 年龄计算。

---

## 9. 需要的支撑

- 语言：class、Bool、Long；
- 运行时：无；
- 接口：`ByteStream`、`PoolKey`。

---

## 10. 依赖的特性/接口/类

`ByteStream`、`PoolKey`。

---

## 11. 所有权与并发

借用视图；流归池；不可变；可共享视图但连接不应并发借用/释放。

---

## 12. 示例与反例

正确：`PooledConnection c = pool.acquire(ctx,key).value(); c.stream().writeAll(...); pool.release(c)`。  
反例：release 后继续用 stream；重复 release；把 age 当墙钟。

---

## 13. 测试/场景义务

创建/复用标志；stream/key；age；release 后池状态；重复 release 合同错误。

---

## 14. XNull 伪代码

```xnull
class PooledConnection {
    final ByteStream _stream
    final PoolKey _key
    final Bool _reused
    final Long _createdMonoMillis

    PooledConnection(ByteStream stream, PoolKey key, Bool reused, Long createdMonoMillis) {
        if stream == null || key == null { throw "PooledConnection: null argument" }
        if createdMonoMillis < 0 { throw "PooledConnection: negative time" }
        _stream = stream
        _key = key
        _reused = reused
        _createdMonoMillis = createdMonoMillis
    }

    ByteStream stream() { return _stream }
    PoolKey key() { return _key }
    Bool isReused() { return _reused }
    Long createdMonoMillis() { return _createdMonoMillis }

    Long ageMillis(Long nowMonoMillis) {
        Long age = nowMonoMillis - _createdMonoMillis
        if age < 0 { return 0 }
        return age
    }
}
```
