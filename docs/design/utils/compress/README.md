# `xdk.compress` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.compress` |
| 层 | L4 数据/编码（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.fs` |
| 被依赖 | HTTP/存储/应用 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

压缩/归档：gzip、zlib、deflate、zstd、lz4、brotli、zip、tar。

不做：加密压缩、流式 tar/zip（X）、流式压缩器（X）、7z/rar、字典训练/自定义字典（X）。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 失败明确 | 数据损坏 `DataCorrupted`；格式不支持 `Unsupported` |
| 资源关闭 | ZipArchive/ZipWriter close 幂等 |
| 无全局 | 无全局压缩器/缓存 |
| 不猜格式 | `is*` 只做魔数/头检查；Brotli 无可靠魔数，不提供 `isBrotli` |
| 内存有界 | 单流解压提供 `decompressWithLimit`，默认 64 MiB；归档另受 `ZipOptions` 限额；X 流式 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `CompressionLevel` | enum | 压缩级别 | [`CompressionLevel.md`](CompressionLevel.md) |
| `Gzip` | class | gzip 压缩/解压 | [`Gzip.md`](Gzip.md) |
| `Zlib` | class | zlib 压缩/解压 | [`Zlib.md`](Zlib.md) |
| `Deflate` | class | raw deflate | [`Deflate.md`](Deflate.md) |
| `Zstd` | class | zstd 压缩/解压 | [`Zstd.md`](Zstd.md) |
| `Lz4` | class | LZ4 帧压缩/解压 | [`Lz4.md`](Lz4.md) |
| `Brotli` | class | Brotli 压缩/解压 | [`Brotli.md`](Brotli.md) |
| `ZipEntry` | class | zip 条目 | [`ZipEntry.md`](ZipEntry.md) |
| `ZipOptions` | class | zip 选项 | [`ZipOptions.md`](ZipOptions.md) |
| `ZipArchive` | class | 读取 zip | [`ZipArchive.md`](ZipArchive.md) |
| `ZipWriter` | class | 写 zip | [`ZipWriter.md`](ZipWriter.md) |
| `TarEntry` | class | tar 条目 | [`TarEntry.md`](TarEntry.md) |
| `Tar` | class | tar 读写 | [`Tar.md`](Tar.md) |

当前 10/13 已实现：`CompressionLevel`、`Gzip`、`Zlib`、`Deflate`、`TarEntry`、`Tar`、
`ZipEntry`、`ZipOptions`、`ZipArchive`、`ZipWriter`；
`Zstd`、`Lz4`、`Brotli` 仍为 planned（3 个）。

X：流式 tar/zip、流式 zstd/lz4/brotli。

---

## 4. 顶层函数

无。

---

## 5. 技术/支撑/依赖

- 技术：gzip/zlib/deflate、zstd 帧、LZ4 帧、Brotli、zip 目录、tar 头。
- 支撑：`gzip*Raw`、`zlib*Raw`、`deflate*Raw`、`zstd*Raw`、`lz4*Raw`、`brotli*Raw`、`zip*Raw`、`tar*Raw`。
- 依赖：`errors`、`bytes`、`fs`。

---

## 6. 场景

### Z1：HTTP gzip

`Gzip.compress`/`decompress`；`isGzip` 检查。

### Z2：归档读取

`ZipArchive.open(path, options)` 或 `openBytes(data, options)`；entries/get/readEntry；extractTo。

### Z3：归档写出

`new ZipWriter(options)`；addFile/addDirectory；finish/close。

### Z4：tar 备份

`Tar.write(entries)`；`Tar.read(bytes)`。

### Z5：zstd 存储

`Zstd.compress(data, CompressionLevel.Default)`；`isZstd` 检查帧魔数；`decompressWithLimit` 限额解压。

### Z6：LZ4 低延迟帧

`Lz4.compress(data, CompressionLevel.Fastest)`；`isLz4` 检查帧魔数；适合日志/缓存等低延迟路径。

### Z7：Brotli Web 文本

`Brotli.compress(data, CompressionLevel.Default)`；格式由 `Content-Encoding: br` 或协议字段确定；`Brotli.decompressWithLimit` 限额解压。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| Zstd/LZ4/Brotli | （`preview`）已支持；各自独立类型，复用 `CompressionLevel` |
| Brotli 魔数 | 无可靠魔数，不提供 `isBrotli`；格式由协议字段或调用方显式确定 |
| 压缩级别 | 复用 `CompressionLevel`，不新增算法专用枚举 |
| 解压上限 | Gzip/Zlib/Deflate/Zstd/Lz4/Brotli 均提供 `decompressWithLimit`；默认 64 MiB；超限 `InvalidArgument` |
| 流式 zip/tar | X |
| 流式压缩器 | X |
| 字典训练/自定义字典 | X |
| 加密压缩 | 不做 |
| 7z/rar | 不做 |
| 解压炸弹 |  用 `ZipOptions`/`decompressWithLimit` 限额；X 流式限额 |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Builder`、`@Override` |
| 处理器 | 标准 A8 / 编译器内建 |
| 生成物 | 压缩条目/选项值语义、归档句柄签名 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `ZipEntry`/`TarEntry` | `@Value` | 值语义成员 |
| `ZipOptions` | `@Builder` | 选项构造 |
| `ZipArchive`/`ZipWriter` | `@Override` | 关闭/写入签名 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
