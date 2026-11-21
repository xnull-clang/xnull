# `ByteArrayWriter`

| 项 | 值 |
| --- | --- |
| 类型 | `class ByteArrayWriter implements Writer, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `stable` |
| 依赖 | `Bytes` |

---

## 1. 定位

内存字节写流；追加写，最后 `toBytes`/`takeBytes`。

不做：定位写、文件/网络、线程安全。

---

## 2. 设计逻辑

- 字段 `_data: Bytes`、`_open: Bool`。
- `write` 追加全部（内存流不会短写）；`writeAll` 同义。
- `toBytes` 副本；`takeBytes` 转移并清空。
- close no-op；关闭后写返回 `Unavailable`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_data` | `Bytes` | 已写内容 |
| `_open` | `Bool` | 是否可用 |

不变量：长度 = 已写字节；非线程安全。

---

## 4. 生命周期

构造空；无资源；close 幂等。

---

## 5. 构造契约

`ByteArrayWriter()` 空。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `write` | 写 | `Context, Bytes data` | `Result<Int, Error>` | `Unavailable` |
| `writeAll` | 写全 | 同上 | `Result<Unit, Error>` | `Unavailable` |
| `flush` | no-op | 无 | `Result<Unit, Error>` | 无 |
| `toBytes` | 副本 | 无 | `Bytes` | 无 |
| `takeBytes` | 转移 | 无 | `Bytes` | 无 |
| `length` | 长度 | 无 | `Int` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | 无 |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 追加缓冲；
- 副本/转移；
- no-op close。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Bool、Result；
- 运行时：字节追加；
- 接口：`Writer`、`Closer`。

---

## 10. 依赖的特性/接口/类

`Writer`、`Closer`、`Bytes`。

---

## 11. 所有权与并发

持有 `_data`；`toBytes` 副本；`takeBytes` 转移；非线程安全。

---

## 12. 示例与反例

正确：write 后 toBytes；takeBytes 后 writer 清空。  
反例：close 后继续写；把 toBytes 当视图；多任务共享。

---

## 13. 测试/场景义务

空/追加/clear；toBytes 副本；takeBytes 转移；close 后；length。

---

## 14. XNull 伪代码

```xnull
class ByteArrayWriter implements Writer, Closer {
    Bytes _data
    Bool _open

    ByteArrayWriter() {
        _data = Bytes.empty()
        _open = true
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "writer closed"))
        }
        _data.pushAll(data)
        return Ok(data.length())
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        Result<Int, Error> result = self.write(context, data)
        if result.isErr() { return Err(result.error()) }
        return Ok(unit)
    }

    Result<Unit, Error> flush() { return Ok(unit) }

    Bytes toBytes() { return copy(_data) }

    Bytes takeBytes() {
        Bytes result = _data
        _data = Bytes.empty()
        return result
    }

    Int length() { return _data.length() }

    void clear() { _data = Bytes.empty() }

    Result<Unit, Error> close() { _open = false; return Ok(unit) }
    Bool isOpen() { return _open }
}
```

> `Bytes.pushAll` 是 `BytesBuilder.append` 等价的内部批量追加；实现可复用 `BytesBuilder`。
