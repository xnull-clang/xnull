# `LimitWriter`

| 项 | 值 |
| --- | --- |
| 类型 | `class LimitWriter implements Writer, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Writer` |

---

## 1. 定位

限制最多写入 N 字节；用于配额/帧大小上限。

不做：截断写入、定位、缓冲。

---

## 2. 设计逻辑

- 字段 `_target: Writer`、`_remaining: Long`、`_open`。
- `write` 要求 `data.length <= remaining`，否则 `InvalidArgument`；成功递减。
- `writeAll` 复用 `write`。
- `close` 关闭目标；幂等。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_target` | `Writer` | 目标 |
| `_remaining` | `Long` | 剩余额度 |
| `_open` | `Bool` | 可用 |

不变量：remaining ≥0；写入不超过额度。

---

## 4. 生命周期

构造后使用；close 关闭目标。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `LimitWriter(Writer target, Long limit)` | target/limit | target 非 null；limit ≥0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `write` | 限写 | `Context, Bytes data` | `Result<Int, Error>` | `InvalidArgument`/`Io` |
| `writeAll` | 写全 | 同上 | `Result<Unit, Error>` | 同上 |
| `remaining` | 剩余 | 无 | `Long` | 无 |
| `flush` | 刷新 | 无 | `Result<Unit, Error>` | `Io` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 额度计数；
- 写入前检查；
- 关闭传播。

---

## 9. 需要的支撑

- 语言：class、Bytes、Long、Int、Bool、Result；
- 运行时：底层 Writer；
- 接口：`Writer`、`Closer`。

---

## 10. 依赖的特性/接口/类

`Writer`、`Closer`、`Bytes`。

---

## 11. 所有权与并发

包装目标；close 传递；单 writer。

---

## 12. 示例与反例

正确：配额 1MB，超限返回 Err。  
反例：超限截断写；remaining 0 继续写；多任务共享。

---

## 13. 测试/场景义务

limit 0；恰好/超出；writeAll；flush/close；remaining。

---

## 14. XNull 伪代码

```xnull
class LimitWriter implements Writer, Closer {
    Writer _target
    Long _remaining
    Bool _open

    LimitWriter(Writer target, Long limit) {
        if target == null || limit < 0 {
            throw "LimitWriter: invalid argument"
        }
        _target = target
        _remaining = limit
        _open = true
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "writer closed"))
        }
        if data.length() as Long > _remaining {
            return Err(new BasicError(ErrorKind.InvalidArgument, "write limit exceeded"))
        }
        Result<Int, Error> written = _target.write(context, data)
        if written.isErr() { return Err(written.error()) }
        _remaining = _remaining - written.value() as Long
        return written
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        Result<Int, Error> written = self.write(context, data)
        if written.isErr() { return Err(written.error()) }
        return Ok(unit)
    }

    Long remaining() { return _remaining }
    Result<Unit, Error> flush() { return _target.flush() }

    Result<Unit, Error> close() {
        _open = false
        return _target.close()
    }

    Bool isOpen() { return _open }
}
```
