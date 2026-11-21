# `ShellOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class ShellOptions` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `Bytes`、`Writer` |

---

## 1. 定位

一次命令执行的策略：工作目录基线、环境基线、stdin 字节、超时、终止宽限、输出保留上限、stderr 合并、stdout/stderr 流式 sink。

`ShellOptions` 不描述“运行什么命令”；命令由 `CommandLine` 描述。`ShellOptions` 描述“怎么运行”。

不做：argv 解析、shell 语法、PATH 查找、进程创建、结果对象、退出进程。

---

## 2. 设计逻辑

- 不可变；所有 `with*` 返回新实例。
- `workingDirectory` 与 `environment` 是执行基线；`CommandLine` 的同名设置覆盖它们。
- `inheritEnvironment` 默认 true：以当前进程环境快照为基线；false 时从空环境开始。
- `stdin` 是固定字节；默认空字节（子进程立即看到 EOF）。 不继承父进程交互式 stdin。
- `timeoutMillis == 0` 表示不设超时；大于 0 时从启动到结束计时。超时由 `CommandResult.wait` 执行；`spawn` 后不 `wait` 不会触发。
- `terminateGraceMillis` 是超时后 `Terminate` 到 `Kill` 的宽限期；0 表示直接 `Kill`。实际结束时间可能到 `timeoutMillis + terminateGraceMillis`，不是硬实时截止。
- `maximumOutputBytes` 是**每个流**的保留上限；0 表示不限制。默认 1 MiB。超过上限时继续排空管道，只丢弃多余保留字节，避免子进程因管道写满而阻塞。
- `mergeStderr` 为 true 时，stderr 合并进 stdout；stderr 捕获为空，stderr sink 不接收数据。
- `stdoutSink`/`stderrSink` 是显式流式出口；Shell 只调用 `writeAll`/`flush`，不 close sink。
- 所有数值校验失败都是合同错误（panic）；执行期 I/O 失败由 `CommandResult`/`Shell` 返回 `Result`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_workingDirectory` | `String?` | 基线 cwd；null 表示进程 cwd |
| `_environment` | `Map<String,String>` | 基线环境覆盖 |
| `_inheritEnvironment` | `Bool` | 是否继承当前环境快照 |
| `_stdin` | `Bytes` | 子进程 stdin 字节 |
| `_timeoutMillis` | `Long` | 超时；0 = 不设 |
| `_terminateGraceMillis` | `Long` | 超时后的终止宽限 |
| `_maximumOutputBytes` | `Long` | 每流保留上限；0 = 不限制 |
| `_mergeStderr` | `Bool` | 是否合并 stderr |
| `_stdoutSink` | `Writer?` | 流式 stdout 出口 |
| `_stderrSink` | `Writer?` | 流式 stderr 出口 |

不变量：

- `_workingDirectory` 为 null 或非空、不含 NUL；
- 环境变量名非空、不含 `=` 与 NUL；值非 null、不含 NUL；
- `_stdin` 非 null；
- 三个 `Long` 均 ≥ 0；
- `_mergeStderr` 为 true 时 `_stderrSink` 仍可保存但永不写入；
- 不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享；sink 的所有权仍在调用方，`ShellOptions` 不关闭它。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ShellOptions.defaults()` | 无 | 默认策略 | 无 |
| `ShellOptions(String? workingDirectory, Map<String,String> environment, Bool isInheritEnvironment, Bytes stdin, Long timeoutMillis, Long terminateGraceMillis, Long maximumOutputBytes, Bool isMergeStderr, Writer? stdoutSink, Writer? stderrSink)` | 见 §6 的 10 个字段 | 见 §3 | 非法 → panic |

公共构造器只用于完整显式配置；多数调用方从 `defaults()` 派生。构造器参数顺序与 §6 一致。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `defaults` | 默认策略 | 无 | `ShellOptions` | 无 |
| `workingDirectory` | 基线 cwd | 无 | `String?` | 无 |
| `environment` | 环境覆盖快照 | 无 | `Map<String,String>` | 无 |
| `isInheritEnvironment` | 是否继承环境 | 无 | `Bool` | 无 |
| `stdin` | stdin 字节快照 | 无 | `Bytes` | 无 |
| `timeoutMillis` | 超时 | 无 | `Long` | 无 |
| `terminateGraceMillis` | 终止宽限 | 无 | `Long` | 无 |
| `maximumOutputBytes` | 每流保留上限 | 无 | `Long` | 无 |
| `isMergeStderr` | 是否合并 stderr | 无 | `Bool` | 无 |
| `stdoutSink` | stdout 流式出口 | 无 | `Writer?` | 无 |
| `stderrSink` | stderr 流式出口 | 无 | `Writer?` | 无 |
| `withWorkingDirectory` | 派生 cwd | `String path` | `ShellOptions` | 空/null/NUL → panic |
| `withoutWorkingDirectory` | 清除 cwd | 无 | `ShellOptions` | 无 |
| `withEnvironment` | 派生环境覆盖 | `String name, String value` | `ShellOptions` | 非法 → panic |
| `withEnvironmentAll` | 批量环境覆盖 | `Map<String,String> values` | `ShellOptions` | 非法 → panic |
| `withInheritEnvironment` | 派生继承开关 | `Bool value` | `ShellOptions` | 无 |
| `withStdinBytes` | 派生 stdin 字节 | `Bytes bytes` | `ShellOptions` | null → panic |
| `withStdinText` | 派生 stdin 文本 | `String text` | `ShellOptions` | null → panic |
| `withTimeoutMillis` | 派生超时 | `Long value` | `ShellOptions` | 负值 → panic |
| `withTerminateGraceMillis` | 派生终止宽限 | `Long value` | `ShellOptions` | 负值 → panic |
| `withMaximumOutputBytes` | 派生保留上限 | `Long value` | `ShellOptions` | 负值 → panic |
| `withMergeStderr` | 派生合并开关 | `Bool value` | `ShellOptions` | 无 |
| `withStdoutSink` | 派生 stdout sink | `Writer writer` | `ShellOptions` | null → panic |
| `withoutStdoutSink` | 清除 stdout sink | 无 | `ShellOptions` | 无 |
| `withStderrSink` | 派生 stderr sink | `Writer writer` | `ShellOptions` | null → panic |
| `withoutStderrSink` | 清除 stderr sink | 无 | `ShellOptions` | 无 |
| `describe` | 诊断摘要（不含值） | 无 | `String` | 无 |

默认值：

| 字段 | 默认 |
| --- | --- |
| workingDirectory | null（进程 cwd） |
| environment | 空覆盖 |
| inheritEnvironment | true |
| stdin | 空字节 |
| timeoutMillis | 0（不设超时） |
| terminateGraceMillis | 2000 |
| maximumOutputBytes | 1048576（1 MiB/流） |
| mergeStderr | false |
| stdoutSink/stderrSink | null |

说明：

- `withEnvironment` 只覆盖一个键；不会 unset 继承来的变量。需要精确环境时先 `withInheritEnvironment(false)`。
- `stdin` 默认空字节；Shell 在命令结束时关闭 stdin 管道。
- 输出上限按捕获的每个流计算；sink 收到的数据不受该上限限制，sink 自身必须限流。
- `describe` 只显示 cwd 值、环境覆盖个数、stdin 字节数、超时/宽限、上限、合并和 sink 有无；不显示 stdin 内容、环境值或 sink 内容。

---

## 8. 使用的技术

- 不可变值对象；
- builder 风格派生；
- 环境/目录校验；
- 字节快照；
- 可选 writer 引用。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、Long、List、Map；
- 运行时：无；
- 接口：`Bytes`、`Bytes.fromUtf8`、`copy(Bytes)`、`Writer`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`Writer`。不依赖 `Env`/`Platform`；环境与 cwd 的解析由 `Shell` 在执行时完成。

---

## 11. 所有权与并发

不可变；`environment`/`stdin` 返回副本；sink 是借用引用，调用方负责其生命周期与并发；`ShellOptions` 可共享，但同一个 sink 不应被多个执行并发写入。未提供 `equals`/哈希；按字段比较由调用方完成。

---

## 12. 示例与反例

正确：

```xnull
ShellOptions options = ShellOptions.defaults()
    .withWorkingDirectory("/work")
    .withEnvironment("LANG", "C")
    .withTimeoutMillis(30000)
    .withMaximumOutputBytes(262144)
    .withMergeStderr(true)
```

反例：

- `withTimeoutMillis(-1)`；
- 期望 `withEnvironment` 删除继承变量；
- 期望 `ShellOptions` close 传入的 `Writer`；
- 期望 `maximumOutputBytes` 限制 sink 的写入量；
- 把 stdin 当交互式终端（ 只支持固定字节）。

---

## 13. 测试/场景义务

默认值；cwd 派生/清除；环境覆盖；inherit true/false；stdin 字节/文本；超时 0/正值；宽限 0/正值；上限 0/正值；合并 stderr；sink 设置/清除；`describe` 不含值；非法数值/名称 panic；副本独立性。

---

## 14. XNull 伪代码

```xnull
class ShellOptions {
    final String? _workingDirectory
    final Map<String, String> _environment
    final Bool _inheritEnvironment
    final Bytes _stdin
    final Long _timeoutMillis
    final Long _terminateGraceMillis
    final Long _maximumOutputBytes
    final Bool _mergeStderr
    final Writer? _stdoutSink
    final Writer? _stderrSink

    ShellOptions(String? workingDirectory, Map<String, String> environment,
                 Bool isInheritEnvironment, Bytes stdin, Long timeoutMillis,
                 Long terminateGraceMillis, Long maximumOutputBytes,
                 Bool isMergeStderr, Writer? stdoutSink, Writer? stderrSink) {
        if workingDirectory != null {
            String directory = workingDirectory as String
            if directory == "" || directory.indexOf("\0") >= 0 {
                throw "ShellOptions: invalid working directory"
            }
        }
        if environment == null || stdin == null {
            throw "ShellOptions: null field"
        }
        if timeoutMillis < 0 || terminateGraceMillis < 0 || maximumOutputBytes < 0 {
            throw "ShellOptions: negative number"
        }
        Map<String, String> copiedEnvironment = [:]
        List<String> keys = environment.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if key == null || key == "" || key.indexOf("=") >= 0 || key.indexOf("\0") >= 0 {
                throw "ShellOptions: invalid environment name"
            }
            String? value = environment.getOr(key, null)
            if value == null || value.indexOf("\0") >= 0 {
                throw "ShellOptions: invalid environment value"
            }
            copiedEnvironment.put(key, value as String)
            index = index + 1
        }
        _workingDirectory = workingDirectory
        _environment = copiedEnvironment
        _inheritEnvironment = isInheritEnvironment
        _stdin = copy(stdin)
        _timeoutMillis = timeoutMillis
        _terminateGraceMillis = terminateGraceMillis
        _maximumOutputBytes = maximumOutputBytes
        _mergeStderr = isMergeStderr
        _stdoutSink = stdoutSink
        _stderrSink = stderrSink
    }

    static ShellOptions defaults() {
        return new ShellOptions(null, [:], true, Bytes.empty(), 0, 2000, 1048576, false, null, null)
    }

    String? workingDirectory() { return _workingDirectory }
    Map<String, String> environment() { return _environment.copy() }
    Bool isInheritEnvironment() { return _inheritEnvironment }
    Bytes stdin() { return copy(_stdin) }
    Long timeoutMillis() { return _timeoutMillis }
    Long terminateGraceMillis() { return _terminateGraceMillis }
    Long maximumOutputBytes() { return _maximumOutputBytes }
    Bool isMergeStderr() { return _mergeStderr }
    Writer? stdoutSink() { return _stdoutSink }
    Writer? stderrSink() { return _stderrSink }

    ShellOptions withWorkingDirectory(String path) {
        if path == null || path == "" || path.indexOf("\0") >= 0 {
            throw "ShellOptions.withWorkingDirectory: invalid path"
        }
        return new ShellOptions(path, _environment, _inheritEnvironment, _stdin,
            _timeoutMillis, _terminateGraceMillis, _maximumOutputBytes,
            _mergeStderr, _stdoutSink, _stderrSink)
    }

    ShellOptions withoutWorkingDirectory() {
        return new ShellOptions(null, _environment, _inheritEnvironment, _stdin,
            _timeoutMillis, _terminateGraceMillis, _maximumOutputBytes,
            _mergeStderr, _stdoutSink, _stderrSink)
    }

    ShellOptions withEnvironment(String name, String value) {
        if name == null || name == "" || name.indexOf("=") >= 0 || name.indexOf("\0") >= 0 {
            throw "ShellOptions.withEnvironment: invalid name"
        }
        if value == null || value.indexOf("\0") >= 0 {
            throw "ShellOptions.withEnvironment: invalid value"
        }
        Map<String, String> environment = _environment.copy()
        environment.put(name, value)
        return new ShellOptions(_workingDirectory, environment, _inheritEnvironment, _stdin,
            _timeoutMillis, _terminateGraceMillis, _maximumOutputBytes,
            _mergeStderr, _stdoutSink, _stderrSink)
    }

    ShellOptions withEnvironmentAll(Map<String, String> values) {
        if values == null {
            throw "ShellOptions.withEnvironmentAll: null values"
        }
        Map<String, String> environment = _environment.copy()
        List<String> keys = values.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if key == null || key == "" || key.indexOf("=") >= 0 || key.indexOf("\0") >= 0 {
                throw "ShellOptions.withEnvironmentAll: invalid name"
            }
            String? value = values.getOr(key, null)
            if value == null || value.indexOf("\0") >= 0 {
                throw "ShellOptions.withEnvironmentAll: invalid value"
            }
            environment.put(key, value as String)
            index = index + 1
        }
        return new ShellOptions(_workingDirectory, environment, _inheritEnvironment, _stdin,
            _timeoutMillis, _terminateGraceMillis, _maximumOutputBytes,
            _mergeStderr, _stdoutSink, _stderrSink)
    }

    ShellOptions withInheritEnvironment(Bool value) {
        return new ShellOptions(_workingDirectory, _environment, value, _stdin,
            _timeoutMillis, _terminateGraceMillis, _maximumOutputBytes,
            _mergeStderr, _stdoutSink, _stderrSink)
    }

    ShellOptions withStdinBytes(Bytes bytes) {
        if bytes == null { throw "ShellOptions.withStdinBytes: null bytes" }
        return new ShellOptions(_workingDirectory, _environment, _inheritEnvironment, bytes,
            _timeoutMillis, _terminateGraceMillis, _maximumOutputBytes,
            _mergeStderr, _stdoutSink, _stderrSink)
    }

    ShellOptions withStdinText(String text) {
        if text == null { throw "ShellOptions.withStdinText: null text" }
        return self.withStdinBytes(Bytes.fromUtf8(text))
    }

    ShellOptions withTimeoutMillis(Long value) {
        if value < 0 { throw "ShellOptions.withTimeoutMillis: negative" }
        return new ShellOptions(_workingDirectory, _environment, _inheritEnvironment, _stdin,
            value, _terminateGraceMillis, _maximumOutputBytes,
            _mergeStderr, _stdoutSink, _stderrSink)
    }

    ShellOptions withTerminateGraceMillis(Long value) {
        if value < 0 { throw "ShellOptions.withTerminateGraceMillis: negative" }
        return new ShellOptions(_workingDirectory, _environment, _inheritEnvironment, _stdin,
            _timeoutMillis, value, _maximumOutputBytes,
            _mergeStderr, _stdoutSink, _stderrSink)
    }

    ShellOptions withMaximumOutputBytes(Long value) {
        if value < 0 { throw "ShellOptions.withMaximumOutputBytes: negative" }
        return new ShellOptions(_workingDirectory, _environment, _inheritEnvironment, _stdin,
            _timeoutMillis, _terminateGraceMillis, value,
            _mergeStderr, _stdoutSink, _stderrSink)
    }

    ShellOptions withMergeStderr(Bool value) {
        return new ShellOptions(_workingDirectory, _environment, _inheritEnvironment, _stdin,
            _timeoutMillis, _terminateGraceMillis, _maximumOutputBytes,
            value, _stdoutSink, _stderrSink)
    }

    ShellOptions withStdoutSink(Writer writer) {
        if writer == null { throw "ShellOptions.withStdoutSink: null writer" }
        return new ShellOptions(_workingDirectory, _environment, _inheritEnvironment, _stdin,
            _timeoutMillis, _terminateGraceMillis, _maximumOutputBytes,
            _mergeStderr, writer, _stderrSink)
    }

    ShellOptions withoutStdoutSink() {
        return new ShellOptions(_workingDirectory, _environment, _inheritEnvironment, _stdin,
            _timeoutMillis, _terminateGraceMillis, _maximumOutputBytes,
            _mergeStderr, null, _stderrSink)
    }

    ShellOptions withStderrSink(Writer writer) {
        if writer == null { throw "ShellOptions.withStderrSink: null writer" }
        return new ShellOptions(_workingDirectory, _environment, _inheritEnvironment, _stdin,
            _timeoutMillis, _terminateGraceMillis, _maximumOutputBytes,
            _mergeStderr, _stdoutSink, writer)
    }

    ShellOptions withoutStderrSink() {
        return new ShellOptions(_workingDirectory, _environment, _inheritEnvironment, _stdin,
            _timeoutMillis, _terminateGraceMillis, _maximumOutputBytes,
            _mergeStderr, _stdoutSink, null)
    }

    String describe() {
        String directory = "process"
        if _workingDirectory != null {
            directory = _workingDirectory as String
        }
        return "cwd=" + directory + " env=" + str(_environment.length())
            + " inherit=" + str(_inheritEnvironment)
            + " stdin=" + str(_stdin.length()) + "B"
            + " timeout=" + str(_timeoutMillis) + "ms"
            + " grace=" + str(_terminateGraceMillis) + "ms"
            + " outputLimit=" + str(_maximumOutputBytes) + "B"
            + " merge=" + str(_mergeStderr)
            + " stdoutSink=" + str(_stdoutSink != null)
            + " stderrSink=" + str(_stderrSink != null)
    }
}
```
