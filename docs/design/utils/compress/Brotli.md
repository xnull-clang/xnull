# `Brotli`

| 项 | 值 |
| --- | --- |
| 类型 | `class Brotli` |
| 包 | `xdk.compress` |
| 稳定性 | `preview` |
| 依赖 | `CompressionLevel`、`Bytes`、`Error` |

---

## 1. 定位

Brotli（RFC 7932）静态入口：压缩、解压、限额解压。

不做：`isBrotli` 魔数判断（Brotli 无可靠魔数）、流式 Reader/Writer（X）、自定义/共享字典（X）、加密。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- `compress` 输出单个完整 Brotli 流；Brotli 没有容器头，流本身即格式。
- 复用 `CompressionLevel`；`None` 映射为未压缩 meta-block，其余四档映射到 Brotli 后端的稳定 quality 子集；输出始终是合法流。
- `decompress` 默认最多 64 MiB 输出，防止解压炸弹；需要更大时显式 `decompressWithLimit`。
- 不提供 `isBrotli`：Brotli 没有可靠魔数，不能靠试探解压猜格式；格式必须由协议字段或调用方显式确定。
- 失败：参数非法 `InvalidArgument`；数据损坏 `DataCorrupted`；超限 `InvalidArgument`。
- 无 close；可并发。

---

## 3. 表示与不变量

无实例字段。

不变量：输入/输出均为完整字节序列；`compress` 输出恰好一个完整 Brotli 流；`decompress` 消费整个输入，尾随字节按 `DataCorrupted` 处理；解压不修改入参；限额只限制输出；超限不返回部分数据。

---

## 4. 生命周期

静态命名空间；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Brotli()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `compress` | Brotli 压缩 | `Bytes data, CompressionLevel level` | `Result<Bytes, Error>` | 参数/后端 |
| `decompress` | Brotli 解压 | `Bytes data` | `Result<Bytes, Error>` | `DataCorrupted`/`InvalidArgument` |
| `decompressWithLimit` | 限额解压 | `Bytes data, Int maximumBytes` | `Result<Bytes, Error>` | `DataCorrupted`/`InvalidArgument` |

说明：

- `decompress` 等价于 `decompressWithLimit(data, 67108864)`。
- `maximumBytes` 必须 >0；输出超过上限返回 `InvalidArgument`，不返回部分数据。
- 无 `isBrotli`；需要格式判断时由上层协议（如 `Content-Encoding: br`）或显式协商提供。

---

## 8. 使用的技术

- RFC 7932 流格式；
- 内建静态字典；
- 上下文建模与 meta-block；
- 输出上限。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Result；
- 运行时：`brotliCompressRaw`、`brotliDecompressRaw`；
- 接口：`CompressionLevel`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`CompressionLevel`、`Bytes`、`Error`、Brotli 运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发；每次调用独立。

---

## 12. 示例与反例

正确：`Brotli.decompressWithLimit(data, 2097152)`；格式由 HTTP `Content-Encoding` 确定。  
反例：尝试 `Brotli.isBrotli`（不存在）；用“先试 Brotli、再试 gzip”猜格式；无上限解压。

---

## 13. 测试/场景义务

已知向量；空载荷；空输入明确失败；随机/高压缩比数据；损坏 meta-block/长度；截断；限额边界；尾随字节；不同级别；非 Brotli 数据返回 `DataCorrupted` 而非格式识别。

---

## 14. XNull 伪代码

```xnull
class Brotli {
    private Brotli() {
    }

    static Result<Bytes, Error> compress(Bytes data, CompressionLevel level) {
        if data == null || level == null {
            throw "Brotli.compress: null argument"
        }
        return brotliCompressRaw(data, level)
    }

    static Result<Bytes, Error> decompress(Bytes data) {
        return Brotli.decompressWithLimit(data, 67108864)
    }

    static Result<Bytes, Error> decompressWithLimit(Bytes data, Int maximumBytes) {
        if data == null { throw "Brotli.decompressWithLimit: null data" }
        if maximumBytes <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "maximumBytes must be positive"))
        }
        return brotliDecompressRaw(data, maximumBytes)
    }
}
```

> `brotli*Raw` 是运行时 Brotli 原语；不是 XDK 公共类型。
