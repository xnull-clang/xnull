# `CommandOutput`

| 项 | 值 |
| --- | --- |
| 类型 | `class CommandOutput` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `Bytes`、`toUtf8`（解码约定） |

---

## 1. 定位

一次命令完成后的不可变输出快照：stdout/stderr 字节、文本视图、按行视图、总字节数、是否合并、是否因上限截断。

与 `xdk.sys.ProcessResult` 的分工：`ProcessResult` 是 sys 级进程结果（String 输出/退出码/耗时）；`CommandOutput` 是 CLI 级输出视图（Bytes/行/截断/合并）；退出码/耗时/信号在 `CommandResult`。

不做：进程句柄、实时读取、写入、解码器注册、终端着色、按行回调。

实时流式由 `ShellOptions` 的 `Writer` sink 负责；`CommandOutput` 只保存完成后可重复读取的值。

---

## 2. 设计逻辑

- 构造时复制 stdout/stderr 字节；字段 `final`。
- `stdoutByteCount`/`stderrByteCount` 是**实际排空的字节数**；`stdout()`/`stderr()` 是**保留的字节**。截断时计数大于保留长度。
- `isTruncated` 表示至少一个流有字节被丢弃；只有保留上限生效时才可能为 true。
- `isMerged` 为 true 时，stderr 保留为空、stderr 计数为 0；合并后的字节在 stdout 中，顺序按 Shell 实际读取顺序。
- 文本视图按 UTF-8 解码；非法序列替换为 U+FFFD，不抛错，因为输出捕获不能因被观察进程的输出损坏而失败。
- 截断可能切断行或 UTF-8 序列；文本/行视图只对保留字节生效，最后一段可能不完整；`isTruncated` 提示。
- 行视图：以 `\n` 分行；行尾 `\r` 去掉（兼容 CRLF）；连续分隔符产生空行；末尾换行不产生额外空行；无结尾换行的最后一段仍是一行；空输出返回空列表。
- 没有 close；可共享；无资源。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_stdout` | `Bytes` | 保留的 stdout 字节 |
| `_stderr` | `Bytes` | 保留的 stderr 字节 |
| `_stdoutByteCount` | `Long` | 排空的 stdout 总字节 |
| `_stderrByteCount` | `Long` | 排空的 stderr 总字节 |
| `_isMerged` | `Bool` | stderr 是否合并进 stdout |
| `_isTruncated` | `Bool` | 是否有字节被丢弃 |

不变量：

- 两个字节容器非 null；
- 两个计数 ≥ 0，且分别 ≥ 对应保留长度；
- `isMerged` 为 true 时，`_stderr.length() == 0` 且 `_stderrByteCount == 0`；
- 未截断时，计数等于保留长度；
- 截断时，至少一个计数大于保留长度；
- 不可变。

---

## 4. 生命周期

构造时冻结；无 close；可共享；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CommandOutput(Bytes stdout, Bytes stderr, Long stdoutByteCount, Long stderrByteCount, Bool isMerged, Bool isTruncated)` | 见 §3 | 非 null；计数 ≥ 保留长度；合并时 stderr 为空 | 非法 → panic |

构造器主要供 `CommandResult` 使用；测试可直接构造合法快照。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `stdout` | stdout 字节副本 | 无 | `Bytes` | 无 |
| `stderr` | stderr 字节副本 | 无 | `Bytes` | 无 |
| `stdoutText` | stdout UTF-8 文本 | 无 | `String` | 无 |
| `stderrText` | stderr UTF-8 文本 | 无 | `String` | 无 |
| `stdoutLines` | stdout 行快照 | 无 | `List<String>` | 无 |
| `stderrLines` | stderr 行快照 | 无 | `List<String>` | 无 |
| `stdoutByteCount` | stdout 总字节 | 无 | `Long` | 无 |
| `stderrByteCount` | stderr 总字节 | 无 | `Long` | 无 |
| `isMerged` | stderr 是否合并 | 无 | `Bool` | 无 |
| `isTruncated` | 是否截断 | 无 | `Bool` | 无 |
| `isEmpty` | 两流是否都为空 | 无 | `Bool` | 无 |
| `describe` | 诊断摘要（不含内容） | 无 | `String` | 无 |

说明：

- `stdout`/`stderr` 每次返回新副本；调用方修改不影响快照。
- `stdoutText`/`stderrText` 只解码保留字节；截断时文本不包含被丢弃部分。
- `stdoutLines`/`stderrLines` 每次重新计算；不缓存，避免共享可变列表。
- `describe` 只显示计数、保留长度、合并/截断标志，不显示输出内容。

---

## 8. 使用的技术

- 不可变快照；
- 字节复制；
- UTF-8 解码（替换非法序列）；
- 行切分（LF/CRLF）；
- 计数与保留量分离。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、Long、List；
- 运行时：UTF-8 解码、字节复制；
- 接口：`Bytes`、`toUtf8`、`copy(Bytes)`、`slice(Bytes, Int, Int)`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`toUtf8`、`copy(Bytes)`。不依赖 `Reader`/`Writer`/`Process`。

---

## 11. 所有权与并发

不可变；字节/行/文本返回副本或新列表；可跨任务共享；无 close；无锁。未提供 `equals`/哈希；按内容比较使用 `stdout`/`stderr` 或计数方法。

---

## 12. 示例与反例

正确：

```xnull
CommandOutput output = result.output()
List<String> lines = output.stdoutLines()
Long total = output.stdoutByteCount()
```

反例：

- 把 `stdoutByteCount` 当保留长度；截断时两者不同；
- 期望 `isMerged` 时 `stderrLines` 仍有内容；
- 期望非法 UTF-8 抛 `DataCorrupted`；
- 修改 `stdout()` 返回的字节并期望影响快照；
- 把 `CommandOutput` 当实时流。

---

## 13. 测试/场景义务

空输出；单行无换行；单行有换行；多行；连续空行；CRLF；孤立 `\r`；非法 UTF-8；截断前半行/半个字符；合并 stderr；计数与保留长度关系；副本独立性；`describe` 不含内容；构造非法计数 panic。

---

## 14. XNull 伪代码

```xnull
class CommandOutput {
    final Bytes _stdout
    final Bytes _stderr
    final Long _stdoutByteCount
    final Long _stderrByteCount
    final Bool _isMerged
    final Bool _isTruncated

    CommandOutput(Bytes stdout, Bytes stderr, Long stdoutByteCount, Long stderrByteCount,
                  Bool isMerged, Bool isTruncated) {
        if stdout == null || stderr == null {
            throw "CommandOutput: null bytes"
        }
        if stdoutByteCount < 0 || stderrByteCount < 0 {
            throw "CommandOutput: negative count"
        }
        if isMerged && (stderr.length() > 0 || stderrByteCount > 0) {
            throw "CommandOutput: merged stderr not empty"
        }
        Long retainedStdout = stdout.length() as Long
        Long retainedStderr = stderr.length() as Long
        if stdoutByteCount < retainedStdout || stderrByteCount < retainedStderr {
            throw "CommandOutput: count smaller than retained"
        }
        if isTruncated {
            if stdoutByteCount == retainedStdout && stderrByteCount == retainedStderr {
                throw "CommandOutput: truncated without dropped bytes"
            }
        } else {
            if stdoutByteCount != retainedStdout || stderrByteCount != retainedStderr {
                throw "CommandOutput: retained mismatch"
            }
        }
        _stdout = copy(stdout)
        _stderr = copy(stderr)
        _stdoutByteCount = stdoutByteCount
        _stderrByteCount = stderrByteCount
        _isMerged = isMerged
        _isTruncated = isTruncated
    }

    Bytes stdout() { return copy(_stdout) }
    Bytes stderr() { return copy(_stderr) }

    String stdoutText() { return toUtf8(_stdout) }
    String stderrText() { return toUtf8(_stderr) }

    List<String> stdoutLines() { return self.splitLines(self.stdoutText()) }
    List<String> stderrLines() { return self.splitLines(self.stderrText()) }

    Long stdoutByteCount() { return _stdoutByteCount }
    Long stderrByteCount() { return _stderrByteCount }
    Bool isMerged() { return _isMerged }
    Bool isTruncated() { return _isTruncated }

    Bool isEmpty() {
        return _stdoutByteCount == 0 && _stderrByteCount == 0
    }

    private List<String> splitLines(String text) {
        List<String> result = []
        Int start = 0
        Int index = 0
        while index < text.length() {
            if text.charAt(index) == '\n' {
                String line = text.substring(start, index - start)
                if line.endsWith("\r") {
                    line = line.substring(0, line.length() - 1)
                }
                result.push(line)
                start = index + 1
            }
            index = index + 1
        }
        if start < text.length() {
            String line = text.substring(start, text.length() - start)
            if line.endsWith("\r") {
                line = line.substring(0, line.length() - 1)
            }
            result.push(line)
        }
        return result
    }

    String describe() {
        return "stdout=" + str(_stdoutByteCount) + "B"
            + " stderr=" + str(_stderrByteCount) + "B"
            + " retained=" + str(_stdout.length()) + "/" + str(_stderr.length()) + "B"
            + " merged=" + str(_isMerged)
            + " truncated=" + str(_isTruncated)
    }
}
```
