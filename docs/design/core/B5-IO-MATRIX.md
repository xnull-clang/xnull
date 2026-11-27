# B5.2-S1 `xdk.io` 22 类型矩阵

| 项 | 值 |
| --- | --- |
| 合同 | `docs/design/core/io/` 22 类型 |
| 源码 | `src/xdk/io/IO.x` |
| 结论 | **15 有实现 / 7 缺失**；B5.2 仍不能闭批 |
| 日期 | 2026-11-27 |

## 已存在（8）

| 合同类型 | 源码现状 | 备注 |
| --- | --- | --- |
| `Reader` | `class Reader implements Readable` | 合同是 protocol；命名/形态有偏差 |
| `Writer` | `class Writer implements Writable` | 同上 |
| `BufferedReader` | 有 | |
| `BufferedWriter` | 有 | |
| `ChainReader` | 有 | |
| `TeeReader` | 有 | |
| `LimitReader` | 有 | |
| `LineReader` | 有 | |
| `Stdio` | 仅 `StdioReader`/`StdioWriter` | 合同要求 `Stdio` facade，缺失 |
| `BufferedWriter` | 有 | 已计 |

> 严格按合同算，`Stdio` 也缺；因此是 8 个类名对应 + 1 个 facade 缺失。

## 已补（2026-11-27，7）

`Seekable`、`Closer`、`SeekOrigin`、`ByteArrayReader`、`ByteArrayWriter`、`StringReader`、`StringWriter`；
`xdk_core` 新增 `xdk_io_2x` 场景。

## 仍缺失（7）

| 类型 | 种类 | 影响 |
| --- | --- | --- |
| `LineWriter` | class | 按行写 |
| `TeeWriter` | class | 双写 |
| `LimitWriter` | class | 限写 |
| `CountingReader` | class | 计数读 |
| `CountingWriter` | class | 计数写 |
| `PeekReader` | class | 预读 |
| `Stdio` | class | 标准流 facade |

## 下一步

1. 补组合流：`LineWriter`、`TeeWriter`、`LimitWriter`、`CountingReader/Writer`、`PeekReader`；
2. 补 `Stdio` facade；
3. 22 类型场景矩阵通过后，再做 S2 fs / S3 sys，最后 S4 批出口。

不得用现有 8 个类名把 22 类型标成完成。
