# `Zstd`

| 项 | 值 |
| --- | --- |
| 类型 | `class Zstd` |
| 包 | `xdk.compress` |
| 稳定性 | `preview` |
| 依赖 | `CompressionLevel`、`Bytes`、`Error` |

---

## 1. 定位

Zstandard（RFC 8878）静态入口：压缩、解压、限额解压、帧魔数判断。

不做：流式 Reader/Writer（X）、字典训练/自定义字典（X）、多帧与可跳过帧拼接策略、加密。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- `compress` 输出单个标准 zstd 帧：魔数 `28 B5 2F FD`、帧头、块序列、可选内容校验和。
- 复用 `CompressionLevel`；`None` 映射为 raw block（仅存储），其余四档映射到 zstd 后端的稳定级别子集；输出始终是合法帧。
- `decompress` 默认最多 64 MiB 输出，防止解压炸弹；需要更大时显式 `decompressWithLimit`。
- `isZstd` 只检查前四字节 `28 B5 2F FD`，不验证帧头、块或校验和；可跳过帧魔数不被识别。
- 失败：参数非法 `InvalidArgument`；数据损坏 `DataCorrupted`；不支持的帧变体 `Unsupported`；超限 `InvalidArgument`。
- 无 close；可并发。

---

## 3. 表示与不变量

无实例字段。

不变量：输入/输出均为完整字节序列；`compress` 输出恰好一个标准帧；`decompress` 只接受单个标准帧；解压不修改入参；限额只限制输出；超限不返回部分数据。

---

## 4. 生命周期

静态命名空间；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Zstd()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `compress` | zstd 压缩 | `Bytes data, CompressionLevel level` | `Result<Bytes, Error>` | 参数/后端 |
| `decompress` | zstd 解压 | `Bytes data` | `Result<Bytes, Error>` | `DataCorrupted`/`Unsupported`/`InvalidArgument` |
| `decompressWithLimit` | 限额解压 | `Bytes data, Int maximumBytes` | `Result<Bytes, Error>` | `DataCorrupted`/`Unsupported`/`InvalidArgument` |
| `isZstd` | 帧魔数判断 | `Bytes data` | `Bool` | null → panic |

说明：

- `decompress` 等价于 `decompressWithLimit(data, 67108864)`。
- `maximumBytes` 必须 >0；输出超过上限返回 `InvalidArgument`，不返回部分数据。
-  只处理单帧；第二帧或可跳过帧返回 `Unsupported`，尾随非帧字节返回 `DataCorrupted`；X 再定义拼接策略。

---

## 8. 使用的技术

- RFC 8878 帧格式；
- FSE/Huffman 熵编码；
- 可选 xxHash64（低 32 位）内容校验；
- 输出上限。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Bool、Result；
- 运行时：`zstdCompressRaw`、`zstdDecompressRaw`、`zstdIsRaw`；
- 接口：`CompressionLevel`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`CompressionLevel`、`Bytes`、`Error`、zstd 运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发；每次调用独立。

---

## 12. 示例与反例

正确：`Zstd.decompressWithLimit(data, 8388608)`。  
反例：用 `isZstd` 当完整性校验；无上限解压不可信输入；把 zstd 帧当 gzip/zlib；依赖多帧拼接。

---

## 13. 测试/场景义务

已知向量；空载荷；随机/高压缩比数据；损坏魔数/帧头/校验和；截断；限额边界；`isZstd` 真/假阳性；多帧与可跳过帧明确 `Unsupported`；不同级别。

---

## 14. XNull 伪代码

```xnull
class Zstd {
    private Zstd() {
    }

    static Result<Bytes, Error> compress(Bytes data, CompressionLevel level) {
        if data == null || level == null {
            throw "Zstd.compress: null argument"
        }
        return zstdCompressRaw(data, level)
    }

    static Result<Bytes, Error> decompress(Bytes data) {
        return Zstd.decompressWithLimit(data, 67108864)
    }

    static Result<Bytes, Error> decompressWithLimit(Bytes data, Int maximumBytes) {
        if data == null { throw "Zstd.decompressWithLimit: null data" }
        if maximumBytes <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "maximumBytes must be positive"))
        }
        return zstdDecompressRaw(data, maximumBytes)
    }

    static Bool isZstd(Bytes data) {
        if data == null { throw "Zstd.isZstd: null data" }
        return zstdIsRaw(data)
    }
}
```

> `zstd*Raw` 是运行时 zstd 原语；不是 XDK 公共类型。
