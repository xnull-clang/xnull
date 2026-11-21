# `Gzip`

| 项 | 值 |
| --- | --- |
| 类型 | `class Gzip` |
| 包 | `xdk.compress` |
| 稳定性 | `preview` |
| 依赖 | `CompressionLevel`、`Bytes`、`Error` |

---

## 1. 定位

gzip（RFC 1952）静态入口：压缩、解压、限额解压、魔数判断。

不做：zlib/deflate 裸流、zip 归档、流式 Reader/Writer（X）、多成员拼接策略。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- `compress` 输出完整 gzip 成员（头、deflate、CRC32、ISIZE）。
- `decompress` 默认最多 64 MiB 输出，防止解压炸弹；需要更大时显式 `decompressWithLimit`。
- `isGzip` 只检查前两字节 `1F 8B`，不验证完整数据。
- 失败：参数非法 `InvalidArgument`；数据损坏 `DataCorrupted`；超限 `InvalidArgument`。
- 无 close；可并发。

---

## 3. 表示与不变量

无实例字段。

不变量：输入/输出均为完整字节序列；解压不修改入参；限额只限制输出。

---

## 4. 生命周期

静态命名空间；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Gzip()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `compress` | gzip 压缩 | `Bytes data, CompressionLevel level` | `Result<Bytes, Error>` | 参数/后端 |
| `decompress` | gzip 解压 | `Bytes data` | `Result<Bytes, Error>` | `DataCorrupted`/`InvalidArgument` |
| `decompressWithLimit` | 限额解压 | `Bytes data, Int maximumBytes` | `Result<Bytes, Error>` | `DataCorrupted`/`InvalidArgument` |
| `isGzip` | 魔数判断 | `Bytes data` | `Bool` | null → panic |

说明：

- `decompress` 等价于 `decompressWithLimit(data, 67108864)`。
- `maximumBytes` 必须 >0；输出超过上限返回 `InvalidArgument`，不返回部分数据。
- 支持单成员 gzip；多成员拼接按 X 明确策略。

---

## 8. 使用的技术

- RFC 1952 头/尾；
- DEFLATE；
- CRC32/ISIZE 校验；
- 输出上限。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Bool、Result；
- 运行时：`gzipCompressRaw`、`gzipDecompressRaw`、`gzipIsRaw`；
- 接口：`CompressionLevel`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`CompressionLevel`、`Bytes`、`Error`、gzip 运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发；每次调用独立。

---

## 12. 示例与反例

正确：`Gzip.decompressWithLimit(data, 1048576)`。  
反例：用 `isGzip` 当完整性校验；无上限解压不可信输入；把 gzip 当 zlib。

---

## 13. 测试/场景义务

已知向量；空数据；随机数据；损坏头/尾/CRC；截断；限额边界；`isGzip` 假阳性；多成员明确失败或策略。

---

## 14. XNull 伪代码

```xnull
class Gzip {
    private Gzip() {
    }

    static Result<Bytes, Error> compress(Bytes data, CompressionLevel level) {
        if data == null || level == null {
            throw "Gzip.compress: null argument"
        }
        return gzipCompressRaw(data, level)
    }

    static Result<Bytes, Error> decompress(Bytes data) {
        return Gzip.decompressWithLimit(data, 67108864)
    }

    static Result<Bytes, Error> decompressWithLimit(Bytes data, Int maximumBytes) {
        if data == null { throw "Gzip.decompressWithLimit: null data" }
        if maximumBytes <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "maximumBytes must be positive"))
        }
        return gzipDecompressRaw(data, maximumBytes)
    }

    static Bool isGzip(Bytes data) {
        if data == null { throw "Gzip.isGzip: null data" }
        return gzipIsRaw(data)
    }
}
```

> `gzip*Raw` 是运行时 gzip 原语；不是 XDK 公共类型。
