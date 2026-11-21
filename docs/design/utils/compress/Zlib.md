# `Zlib`

| 项 | 值 |
| --- | --- |
| 类型 | `class Zlib` |
| 包 | `xdk.compress` |
| 稳定性 | `preview` |
| 依赖 | `CompressionLevel`、`Bytes`、`Error` |

---

## 1. 定位

zlib（RFC 1950）静态入口：压缩、解压、限额解压、头判断。

不做：gzip、raw deflate、zip 归档、流式 API（X）。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- `compress` 输出 zlib 容器（CMF/FLG、deflate、Adler-32）。
- `decompress` 默认最多 64 MiB 输出；`decompressWithLimit` 显式限额。
- `isZlib` 检查 CM=8 且 `(CMF*256+FLG) % 31 == 0`，不验证完整数据。
- 失败分类同 `Gzip`。
- 无 close；可并发。

---

## 3. 表示与不变量

无实例字段。

不变量：输出为完整 zlib 流；解压不修改入参；超限不返回部分结果。

---

## 4. 生命周期

静态命名空间；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Zlib()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `compress` | zlib 压缩 | `Bytes data, CompressionLevel level` | `Result<Bytes, Error>` | 参数/后端 |
| `decompress` | zlib 解压 | `Bytes data` | `Result<Bytes, Error>` | `DataCorrupted`/`InvalidArgument` |
| `decompressWithLimit` | 限额解压 | `Bytes data, Int maximumBytes` | `Result<Bytes, Error>` | `DataCorrupted`/`InvalidArgument` |
| `isZlib` | 头判断 | `Bytes data` | `Bool` | null → panic |

---

## 8. 使用的技术

- RFC 1950 容器；
- DEFLATE；
- Adler-32；
- 输出上限。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Bool、Result；
- 运行时：`zlibCompressRaw`、`zlibDecompressRaw`、`zlibIsRaw`；
- 接口：`CompressionLevel`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`CompressionLevel`、`Bytes`、`Error`、zlib 运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：`Zlib.compress(data, CompressionLevel.Default)`。  
反例：把 zlib 当 gzip；用 `isZlib` 验 CRC；无上限解压不可信输入。

---

## 13. 测试/场景义务

已知向量；空数据；损坏 CMF/FLG/Adler；截断；限额；`isZlib` 边界；与 gzip 区分。

---

## 14. XNull 伪代码

```xnull
class Zlib {
    private Zlib() {
    }

    static Result<Bytes, Error> compress(Bytes data, CompressionLevel level) {
        if data == null || level == null {
            throw "Zlib.compress: null argument"
        }
        return zlibCompressRaw(data, level)
    }

    static Result<Bytes, Error> decompress(Bytes data) {
        return Zlib.decompressWithLimit(data, 67108864)
    }

    static Result<Bytes, Error> decompressWithLimit(Bytes data, Int maximumBytes) {
        if data == null { throw "Zlib.decompressWithLimit: null data" }
        if maximumBytes <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "maximumBytes must be positive"))
        }
        return zlibDecompressRaw(data, maximumBytes)
    }

    static Bool isZlib(Bytes data) {
        if data == null { throw "Zlib.isZlib: null data" }
        return zlibIsRaw(data)
    }
}
```

> `zlib*Raw` 是运行时 zlib 原语；不是 XDK 公共类型。
