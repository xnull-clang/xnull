# `Lz4`

| 项 | 值 |
| --- | --- |
| 类型 | `class Lz4` |
| 包 | `xdk.compress` |
| 稳定性 | `preview` |
| 依赖 | `CompressionLevel`、`Bytes`、`Error` |

---

## 1. 定位

LZ4 帧格式静态入口：压缩、解压、限额解压、帧魔数判断。

不做：raw LZ4 block、legacy 帧、流式 Reader/Writer（X）、字典模式、加密。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- `compress` 输出单个标准 LZ4 帧：魔数 `04 22 4D 18`、帧描述符、块序列、可选内容校验和。
- 复用 `CompressionLevel`；`None` 映射为未压缩块，其余四档映射到 LZ4 后端的加速/高压缩档位；输出始终是合法帧。
- `decompress` 默认最多 64 MiB 输出，防止解压炸弹；需要更大时显式 `decompressWithLimit`。
- `isLz4` 只检查前四字节 `04 22 4D 18`，不验证帧描述符或校验和；legacy 帧魔数 `02 21 4C 18` 不被识别。
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
| `Lz4()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `compress` | LZ4 帧压缩 | `Bytes data, CompressionLevel level` | `Result<Bytes, Error>` | 参数/后端 |
| `decompress` | LZ4 帧解压 | `Bytes data` | `Result<Bytes, Error>` | `DataCorrupted`/`Unsupported`/`InvalidArgument` |
| `decompressWithLimit` | 限额解压 | `Bytes data, Int maximumBytes` | `Result<Bytes, Error>` | `DataCorrupted`/`Unsupported`/`InvalidArgument` |
| `isLz4` | 帧魔数判断 | `Bytes data` | `Bool` | null → panic |

说明：

- `decompress` 等价于 `decompressWithLimit(data, 67108864)`。
- `maximumBytes` 必须 >0；输出超过上限返回 `InvalidArgument`，不返回部分数据。
-  只处理单帧；第二帧或 legacy 帧返回 `Unsupported`，尾随非帧字节返回 `DataCorrupted`；X 再定义拼接策略。

---

## 8. 使用的技术

- LZ4 帧格式；
- LZ4 block 压缩（含未压缩块）；
- xxHash32 头校验、可选块/内容校验；
- 输出上限。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Bool、Result；
- 运行时：`lz4CompressRaw`、`lz4DecompressRaw`、`lz4IsRaw`；
- 接口：`CompressionLevel`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`CompressionLevel`、`Bytes`、`Error`、LZ4 运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发；每次调用独立。

---

## 12. 示例与反例

正确：`Lz4.decompressWithLimit(data, 33554432)`。  
反例：把 raw LZ4 block 传给 `Lz4`；把 legacy 帧当标准帧；用 `isLz4` 当完整性校验；无上限解压。

---

## 13. 测试/场景义务

已知向量；空载荷；不可压缩数据；损坏魔数/帧描述符/校验和；截断；限额边界；`isLz4` 真/假阳性；legacy 帧明确 `Unsupported`；未压缩块；不同级别。

---

## 14. XNull 伪代码

```xnull
class Lz4 {
    private Lz4() {
    }

    static Result<Bytes, Error> compress(Bytes data, CompressionLevel level) {
        if data == null || level == null {
            throw "Lz4.compress: null argument"
        }
        return lz4CompressRaw(data, level)
    }

    static Result<Bytes, Error> decompress(Bytes data) {
        return Lz4.decompressWithLimit(data, 67108864)
    }

    static Result<Bytes, Error> decompressWithLimit(Bytes data, Int maximumBytes) {
        if data == null { throw "Lz4.decompressWithLimit: null data" }
        if maximumBytes <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "maximumBytes must be positive"))
        }
        return lz4DecompressRaw(data, maximumBytes)
    }

    static Bool isLz4(Bytes data) {
        if data == null { throw "Lz4.isLz4: null data" }
        return lz4IsRaw(data)
    }
}
```

> `lz4*Raw` 是运行时 LZ4 原语；不是 XDK 公共类型。
