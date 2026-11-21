# `StringWriter`

| 项 | 值 |
| --- | --- |
| 类型 | `class StringWriter implements Writer, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `StringBuilder`、`toUtf8` |

---

## 1. 定位

内存字符串写流；按 UTF-8 字节写入，最后 `toString`。

不做：文件/网络、定位写、线程安全。

---

## 2. 设计逻辑

- 字段 `_builder: StringBuilder`、`_open: Bool`。
- `write` 把字节解码为 UTF-8 文本后追加；非法字节替换 U+FFFD（或返回 `DataCorrupted`？本设计用替换）。
- `writeText` 直接追加字符串。
- `toString` 返回副本；`clear` 清空。
- close no-op；关闭后写 `Unavailable`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_builder` | `StringBuilder` | 内容 |
| `_open` | `Bool` | 可用 |

不变量：长度 = 已写文本；非线程安全。

---

## 4. 生命周期

构造空；无资源；close 幂等。

---

## 5. 构造契约

`StringWriter()` 空。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `write` | 写字节 | `Context, Bytes data` | `Result<Int, Error>` | `Unavailable` |
| `writeAll` | 写全 | 同上 | `Result<Unit, Error>` | `Unavailable` |
| `writeText` | 写文本 | `String text` | `void` | null → panic |
| `flush` | no-op | 无 | `Result<Unit, Error>` | 无 |
| `toString` | 内容 | 无 | `String` | 无 |
| `length` | 长度 | 无 | `Int` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | 无 |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- UTF-8 解码；
- StringBuilder；
- 副本输出。

---

## 9. 需要的支撑

- 语言：class、String、Bytes、Int、Bool、Result；
- 运行时：UTF-8 解码；
- 接口：`Writer`、`Closer`、`StringBuilder`、`toUtf8`。

---

## 10. 依赖的特性/接口/类

`Writer`、`Closer`、`StringBuilder`、`toUtf8`。

---

## 11. 所有权与并发

持有 builder；`toString` 副本；非线程安全。

---

## 12. 示例与反例

正确：write(fromUtf8("a"))；toString。  
反例：close 后写；把 toString 当实时视图；多任务共享。

---

## 13. 测试/场景义务

ASCII/多字节；非法字节；writeText；length；clear；close。

---

## 14. XNull 伪代码

```xnull
class StringWriter implements Writer, Closer {
    StringBuilder _builder
    Bool _open

    StringWriter() {
        _builder = new StringBuilder()
        _open = true
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "writer closed"))
        }
        _builder.append(toUtf8(data))
        return Ok(data.length())
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        Result<Int, Error> result = self.write(context, data)
        if result.isErr() { return Err(result.error()) }
        return Ok(unit)
    }

    void writeText(String text) {
        if text == null { throw "StringWriter.writeText: null" }
        _builder.append(text)
    }

    Result<Unit, Error> flush() { return Ok(unit) }

    String toString() { return _builder.build() }
    Int length() { return _builder.length() }
    void clear() { _builder.clear() }

    Result<Unit, Error> close() { _open = false; return Ok(unit) }
    Bool isOpen() { return _open }
}
```
