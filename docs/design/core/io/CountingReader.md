# `CountingReader`

| 项 | 值 |
| --- | --- |
| 类型 | `class CountingReader implements Reader, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Reader` |

---

## 1. 定位

统计读取字节数的 Reader 包装器。

不做：限读（LimitReader）、缓冲、定位。

---

## 2. 设计逻辑

- 字段 `_source`、`_count: Long`、`_open`。
- `read` 成功后 `count += 返回值`。
- `close` 关闭源；`resetCount` 清零。
- 单 reader。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_source` | `Reader` | 源 |
| `_count` | `Long` | 已读 |
| `_open` | `Bool` | 可用 |

不变量：count ≥0。

---

## 4. 生命周期

构造后使用；close 关闭源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CountingReader(Reader source)` | source | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `read` | 读并计数 | `Context, Bytes buffer` | `Result<Int, Error>` | `Io`/`Unavailable` |
| `count` | 已读 | 无 | `Long` | 无 |
| `resetCount` | 清零 | 无 | `void` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 计数；
- 委托读；
- 关闭传播。

---

## 9. 需要的支撑

- 语言：class、Bytes、Long、Int、Bool、Result；
- 运行时：底层 Reader；
- 接口：`Reader`、`Closer`。

---

## 10. 依赖的特性/接口/类

`Reader`、`Closer`、`Bytes`。

---

## 11. 所有权与并发

包装源；close 传递；单 reader。

---

## 12. 示例与反例

正确：统计上传/下载字节。  
反例：EOF 后重复 read 期望 count 增加（0 不加）；多任务共享。

---

## 13. 测试/场景义务

计数；EOF；reset；close；错误不增加计数。

---

## 14. XNull 伪代码

```xnull
class CountingReader implements Reader, Closer {
    Reader _source
    Long _count
    Bool _open

    CountingReader(Reader source) {
        if source == null { throw "CountingReader: null source" }
        _source = source
        _count = 0
        _open = true
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "reader closed"))
        }
        Result<Int, Error> read = _source.read(context, buffer)
        if read.isErr() { return Err(read.error()) }
        _count = _count + read.value() as Long
        return read
    }

    Long count() { return _count }
    void resetCount() { _count = 0 }
    Result<Unit, Error> close() { _open = false; return _source.close() }
    Bool isOpen() { return _open }
}
```
