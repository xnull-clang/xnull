# `Deflate`

| 项 | 值 |
| --- | --- |
| 类型 | `class Deflate` |
| 包 | `xdk.compress` |
| 稳定性 | `preview` |
| 依赖 | `CompressionLevel`、`Bytes`、`Error` |

---

## 1. 定位

raw DEFLATE（RFC 1951）静态入口：无容器压缩/解压。

不做：gzip/zlib 头尾、自动格式识别、流式 API（X）。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- raw deflate 没有可靠魔数，因此不提供 `isDeflate`。
- `decompress` 默认最多 64 MiB 输出；`decompressWithLimit` 显式限额。
- 调用方负责知道数据是 raw deflate；通常由 zlib/gzip 容器内部使用。
- 失败分类同 `Gzip`。
- 无 close；可并发。

---

## 3. 表示与不变量

无实例字段。

不变量：输出为 raw DEFLATE 流；不添加容器头尾；解压不修改入参。

---

## 4. 生命周期

静态命名空间；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Deflate()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `compress` | raw 压缩 | `Bytes data, CompressionLevel level` | `Result<Bytes, Error>` | 参数/后端 |
| `decompress` | raw 解压 | `Bytes data` | `Result<Bytes, Error>` | `DataCorrupted`/`InvalidArgument` |
| `decompressWithLimit` | 限额解压 | `Bytes data, Int maximumBytes` | `Result<Bytes, Error>` | `DataCorrupted`/`InvalidArgument` |

---

## 8. 使用的技术

- RFC 1951；
- DEFLATE 块/Huffman；
- 输出上限。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Result；
- 运行时：`deflateCompressRaw`、`deflateDecompressRaw`；
- 接口：`CompressionLevel`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`CompressionLevel`、`Bytes`、`Error`、DEFLATE 运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：从 zlib 容器取出 DEFLATE 段后调用 `Deflate.decompress`。  
反例：把 gzip 数据直接传给 `Deflate`；期望自动识别；无上限解压。

---

## 13. 测试/场景义务

已知向量；空流；损坏块；截断；限额；与 zlib/gzip 组合；不同级别。

---

## 14. XNull 伪代码

```xnull
class Deflate {
    private Deflate() {
    }

    static Result<Bytes, Error> compress(Bytes data, CompressionLevel level) {
        if data == null || level == null {
            throw "Deflate.compress: null argument"
        }
        return deflateCompressRaw(data, level)
    }

    static Result<Bytes, Error> decompress(Bytes data) {
        return Deflate.decompressWithLimit(data, 67108864)
    }

    static Result<Bytes, Error> decompressWithLimit(Bytes data, Int maximumBytes) {
        if data == null { throw "Deflate.decompressWithLimit: null data" }
        if maximumBytes <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "maximumBytes must be positive"))
        }
        return deflateDecompressRaw(data, maximumBytes)
    }
}
```

> `deflate*Raw` 是运行时 DEFLATE 原语；不是 XDK 公共类型。
