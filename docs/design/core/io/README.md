# `xdk.io` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.io` |
| 层 | `xdk.core` / L3 |
| 依赖 | `xdk.errors`、`xdk.bytes` |
| 被依赖 | `fs`、`sys`、`log`、`config`、`net` |
| 稳定性 | 基础 `stable`；组合器 `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.io` 提供流抽象与组合器：

- `Reader`/`Writer`/`Seekable`/`Closer` 协议；
- 内存字节/字符串流；
- Buffered/Line/Chain/Tee/Limit/Counting/Peek；
- 标准输入/输出/错误。

不做：文件/网络/终端实现（fs/net/terminal）、异步 IO、零拷贝。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| EOF | `read` 返回 0 = EOF；不是错误 |
| 短写 | `write` 可短写；`writeAll` 写全 |
| 资源 | 持 OS 资源的流必须 close；内存流 close 幂等 no-op |
| 取消 | 可阻塞流首参 `Context`；内存流不阻塞 |
| 组合 | 组合器包装 Reader/Writer，不改变所有权 |
| 非线程安全 | 单 reader/单 writer；跨任务需外部同步 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Reader` | protocol | 顺序读 | [`Reader.md`](Reader.md) |
| `Writer` | protocol | 顺序写 | [`Writer.md`](Writer.md) |
| `Seekable` | protocol | 定位 | [`Seekable.md`](Seekable.md) |
| `Closer` | protocol | 关闭 | [`Closer.md`](Closer.md) |
| `SeekOrigin` | enum | 起始点 | [`SeekOrigin.md`](SeekOrigin.md) |
| `ByteArrayReader` | class | 内存字节读 | [`ByteArrayReader.md`](ByteArrayReader.md) |
| `ByteArrayWriter` | class | 内存字节写 | [`ByteArrayWriter.md`](ByteArrayWriter.md) |
| `StringReader` | class | 内存字符串读 | [`StringReader.md`](StringReader.md) |
| `StringWriter` | class | 内存字符串写 | [`StringWriter.md`](StringWriter.md) |
| `BufferedReader` | class | 缓冲读 | [`BufferedReader.md`](BufferedReader.md) |
| `BufferedWriter` | class | 缓冲写 | [`BufferedWriter.md`](BufferedWriter.md) |
| `LineReader` | class | 按行读 | [`LineReader.md`](LineReader.md) |
| `LineWriter` | class | 按行写 | [`LineWriter.md`](LineWriter.md) |
| `ChainReader` | class | 串联读 | [`ChainReader.md`](ChainReader.md) |
| `TeeReader` | class | 边读边复制 | [`TeeReader.md`](TeeReader.md) |
| `TeeWriter` | class | 双写 | [`TeeWriter.md`](TeeWriter.md) |
| `LimitReader` | class | 限读 | [`LimitReader.md`](LimitReader.md) |
| `LimitWriter` | class | 限写 | [`LimitWriter.md`](LimitWriter.md) |
| `CountingReader` | class | 计数读 | [`CountingReader.md`](CountingReader.md) |
| `CountingWriter` | class | 计数写 | [`CountingWriter.md`](CountingWriter.md) |
| `PeekReader` | class | 预读 | [`PeekReader.md`](PeekReader.md) |
| `Stdio` | class | 标准流 | [`Stdio.md`](Stdio.md) |

---

## 4. 顶层函数

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `copy` | 复制到 EOF | `Context, Reader, Writer` | `Result<Long, Error>` | `Io`/`Cancelled` |
| `copyN` | 复制 N 字节 | `Context, Reader, Writer, Long count` | `Result<Long, Error>` | `Io`/`Cancelled` |
| `copyBuffer` | 带缓冲复制 | `Context, Reader, Writer, Bytes buffer` | `Result<Long, Error>` | `Io`/`Cancelled` |
| `readAll` | 读全部 | `Context, Reader` | `Result<Bytes, Error>` | `Io`/`Cancelled` |
| `readAllText` | 读全部文本 | `Context, Reader` | `Result<String, Error>` | `Io`/`DataCorrupted` |
| `readFully` | 读满缓冲 | `Context, Reader, Bytes buffer` | `Result<Unit, Error>` | `Io`/`DataCorrupted` |
| `readLine` | 读一行 | `Context, Reader` | `Result<String?, Error>` | `Io`/`Cancelled` |
| `skip` | 跳过 | `Context, Reader, Long count` | `Result<Long, Error>` | `Io`/`Cancelled` |
| `skipFully` | 跳满 | `Context, Reader, Long count` | `Result<Unit, Error>` | `Io`/`DataCorrupted` |
| `pump` | 读并回调 | `Context, Reader, Long(void(Bytes))` | `Result<Long, Error>` | `Io`/`Cancelled` |

### 4.1 技术/支撑/依赖

- 技术：流复制、缓冲区、行切分、计数、限制、预读。
- 支撑：`Bytes`、`Context`、`Result`、`runtime` 取消。
- 依赖：`Reader`、`Writer`、`Bytes`、`Error`、`BasicError`、`ErrorKind`。

### 4.2 关键伪代码

```xnull
Result<Long, Error> copy(Context context, Reader source, Writer target) {
    Bytes buffer = Bytes.alloc(32768)
    Long total = 0
    while true {
        Result<Int, Error> read = source.read(context, buffer)
        if read.isErr() { return Err(read.error()) }
        if read.value() == 0 { break }
        Bytes chunk = slice(buffer, 0, read.value())
        Result<Unit, Error> write = target.writeAll(context, chunk)
        if write.isErr() { return Err(write.error()) }
        total = total + read.value()
    }
    return Ok(total)
}

Result<String?, Error> readLine(Context context, Reader source) {
    Bytes line = Bytes.empty()
    Bytes one = Bytes.alloc(1)
    while true {
        Result<Int, Error> read = source.read(context, one)
        if read.isErr() { return Err(read.error()) }
        if read.value() == 0 {
            if line.isEmpty() { return Ok(null) }
            return Ok(toUtf8(line))
        }
        if one.get(0) == 10 {
            return Ok(toUtf8(line))
        }
        if one.get(0) != 13 {
            line.push(one.get(0))
        }
    }
}
```

---

## 5. 场景

### IO1：文件复制

`File` 实现 `Reader/Writer`；`copy` 分块；`Cancelled` 停止。

### IO2：按行处理配置

`LineReader` + `readLine`；EOF null；不把空行当 EOF。

### IO3：协议帧限读

`LimitReader` + `readExact`；超限 `DataCorrupted`。

### IO4：日志 Tee

`TeeWriter` 同时写控制台和文件；任一失败传播。

### IO5：标准流

`Stdio.stdin/stdout/stderr`；终端判断；不 close 标准流。

---

## 6. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 异步 IO | X； 阻塞流 + Context |
| 零拷贝 |  不做 |
| `read` 0=EOF | 明确；不是错误 |
| `write` 短写 | 允许；`writeAll` 写全 |
| 标准流 close | 不 close |
| 文件/网络流 | 在 fs/net 实现 `Reader/Writer` |
| 线程安全 | 单 reader/单 writer；外部同步 |

## 9. 1.x 已实现 API 回写

- `StdioReader`/`StdioWriter`、`stdinReader()`/`stdoutWriter()`/`stderrWriter()`；
- `readAll`/`copyTo` 与 Buffered/Chain/Tee/Limit/LineReader；
- 1.x `Reader`/`Writer` 具体类保留为 2.x `protocol + ByteArray/String` 的适配来源。

2.x 协议化不删除 1.x 行为；适配器在 2.x 合同中登记。
