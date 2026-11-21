# `CountingWriter`

| 项 | 值 |
| --- | --- |
| 类型 | `class CountingWriter implements Writer, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Writer` |

---

## 1. 定位

统计写入字节数的 Writer 包装器。

不做：限写（LimitWriter）、缓冲、定位。

---

## 2. 设计逻辑

- 字段 `_target`、`_count: Long`、`_open`。
- `write` 成功后 `count += 实际写入`。
- `writeAll` 委托并计数。
- `close` 关闭目标；`resetCount` 清零。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_target` | `Writer` | 目标 |
| `_count` | `Long` | 已写 |
| `_open` | `Bool` | 可用 |

不变量：count ≥0。

---

## 4. 生命周期

构造后使用；close 关闭目标。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CountingWriter(Writer target)` | target | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `write` | 写并计数 | `Context, Bytes data` | `Result<Int, Error>` | `Io`/`Unavailable` |
| `writeAll` | 写全并计数 | 同上 | `Result<Unit, Error>` | 同上 |
| `count` | 已写 | 无 | `Long` | 无 |
| `resetCount` | 清零 | 无 | `void` | 无 |
| `flush` | 刷新 | 无 | `Result<Unit, Error>` | `Io` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 计数；
- 委托写；
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

正确：统计输出字节。  
反例：短写未计数；错误仍计数；多任务共享。

---

## 13. 测试/场景义务

计数；短写；writeAll；flush/close；reset；错误不计数。

---

## 14. XNull 伪代码

```xnull
class CountingWriter implements Writer, Closer {
    Writer _target
    Long _count
    Bool _open

    CountingWriter(Writer target) {
        if target == null { throw "CountingWriter: null target" }
        _target = target
        _count = 0
        _open = true
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "writer closed"))
        }
        Result<Int, Error> written = _target.write(context, data)
        if written.isErr() { return Err(written.error()) }
        _count = _count + written.value() as Long
        return written
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        Result<Unit, Error> written = _target.writeAll(context, data)
        if written.isErr() { return Err(written.error()) }
        _count = _count + data.length() as Long
        return Ok(unit)
    }

    Long count() { return _count }
    void resetCount() { _count = 0 }
    Result<Unit, Error> flush() { return _target.flush() }
    Result<Unit, Error> close() { _open = false; return _target.close() }
    Bool isOpen() { return _open }
}
```
