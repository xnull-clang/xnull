# `CommandLine`

| 项 | 值 |
| --- | --- |
| 类型 | `class CommandLine` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | 无（仅语言容器；环境/目录规则在本文定义） |

---

## 1. 定位

不可变的命令规格：程序名、参数向量、可选工作目录、可选环境覆盖。

它是 `Shell` 的唯一命令输入，让调用方在类型层面把“程序”和“参数”分开，避免把一段命令字符串交给 shell 解释。

不做：解析命令行文本、PATH 查找、glob/变量/管道/重定向展开、shell 解释、执行、读取环境、进程退出。

---

## 2. 设计逻辑

- `program` 与 `arguments` 是两个独立字段；`arguments` 不含 `argv[0]`。
- `fromArgv` 只做“首元素是程序、其余是参数”的机械拆分；不解析引号、不合并 token。
- `program` 可以是裸命令名或路径；是否含空格、是否可执行由 OS 在启动时判断。
- 每个参数原样传给子进程；空格、`*`、`$HOME`、`|`、`>` 都是普通字符。
- `workingDirectory` 是本命令的 cwd；与 `ShellOptions.workingDirectory` 的优先级由 `Shell` 统一解析。
- `environment` 是本命令的环境覆盖；在 `ShellOptions.environment` 之后应用，同名键以本命令为准。
- 不提供 unset 环境变量；需要精确环境时使用 `ShellOptions.withInheritEnvironment(false)` 后显式设置。
- 所有 `with*` 返回新实例；字段 `final`，构造后不可变。
- 非法程序/参数/目录/环境名是合同错误（panic）；不做静默截断或转义。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_program` | `String` | 程序名或路径 |
| `_arguments` | `List<String>` | 参数向量，不含程序名 |
| `_workingDirectory` | `String?` | 本命令 cwd；null 表示交给 `ShellOptions`/进程 cwd |
| `_environment` | `Map<String,String>` | 本命令环境覆盖 |

不变量：

- `_program` 非空、不含 NUL；
- `_arguments` 非 null、元素非 null、元素不含 NUL；
- `_workingDirectory` 为 null 或非空、不含 NUL；
- 环境变量名非空、不含 `=` 与 NUL；环境变量值非 null、不含 NUL；
- 所有容器构造时复制，之后不再修改。

---

## 4. 生命周期

构造后不可变；无 close；可跨任务共享；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CommandLine(String program, List<String> arguments)` | program/arguments | program 非空；arguments 非 null；无 NUL | 非法 → panic |
| `CommandLine.of(String program)` | program | 同 program | 非法 → panic |
| `CommandLine.fromArgv(List<String> tokens)` | tokens | 非空；首元素为程序 | 空/null → panic |

派生方法只接受合法值；非法环境名/目录/参数 → panic。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `program` | 程序名 | 无 | `String` | 无 |
| `arguments` | 参数快照 | 无 | `List<String>` | 无 |
| `argumentCount` | 参数数 | 无 | `Int` | 无 |
| `workingDirectory` | 本命令 cwd | 无 | `String?` | 无 |
| `environment` | 环境覆盖快照 | 无 | `Map<String,String>` | 无 |
| `argv` | 程序 + 参数的完整 argv | 无 | `List<String>` | 无 |
| `withArgument` | 追加一个参数 | `String value` | `CommandLine` | null/NUL → panic |
| `withArguments` | 替换全部参数 | `List<String> values` | `CommandLine` | null/NUL → panic |
| `withWorkingDirectory` | 派生 cwd | `String path` | `CommandLine` | 空/null/NUL → panic |
| `withoutWorkingDirectory` | 清除 cwd | 无 | `CommandLine` | 无 |
| `withEnvironment` | 派生一个环境覆盖 | `String name, String value` | `CommandLine` | 非法 → panic |
| `withEnvironmentAll` | 批量环境覆盖 | `Map<String,String> values` | `CommandLine` | 非法 → panic |
| `describe` | 诊断摘要（不含参数值/环境值） | 无 | `String` | 无 |

说明：

- `arguments`/`argv`/`environment` 返回副本；调用方修改副本不影响命令。
- `argv` 返回 program 后接 arguments 的完整 argv，只用于展示/调试；执行路径始终使用 `program` + `arguments` 分开传递。
- `fromArgv` 不做任何 shell 语法处理：`["echo", "a b", "|", "cat"]` 的第二个参数就是一个含空格的字符串，`|` 是普通参数。
- `describe` 只显示程序名、参数个数、环境覆盖个数和有无 cwd；不显示参数值与环境值，避免把 token/secret 写进日志。

---

## 8. 使用的技术

- 不可变值对象；
- builder 风格派生；
- 列表/映射快照；
- 名称与 NUL 校验；
- argv 拆分（只拆首元素）。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、List、Map；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。`CommandLine` 不依赖 `Command`/`Parser`，也不读取 `Env`/`Platform`；这些由 `Shell` 在执行时解析。

---

## 11. 所有权与并发

`CommandLine` 不可变；`arguments`/`argv`/`environment` 返回副本；可共享；无资源；可作值读取，但不承诺 `Map` 键语义（未提供 `equals`/哈希）。

---

## 12. 示例与反例

正确：

```xnull
CommandLine line = new CommandLine("git", ["status", "--short"])
CommandLine clone = line.withWorkingDirectory("/work/repo").withEnvironment("GIT_TERMINAL_PROMPT", "0")
```

反例：

- `new CommandLine("git status --short", [])`：把整段文本当程序名，不执行 shell 拆分；
- `new CommandLine("sh", ["-c", "echo $HOME"])`：这是调用方显式执行 shell，`Shell` 不会替代其做转义；
- 期望 `*` 被 glob 展开、`$HOME` 被替换、`|` 被当作管道；
- 在日志里直接打印 `argv` 或环境值。

---

## 13. 测试/场景义务

程序为空/null；参数含 null/NUL；带空格参数；含 shell 元字符参数；`fromArgv` 空/单元素/多元素；`argv` 副本独立性；cwd 派生/清除；环境覆盖顺序（`ShellOptions` 之后）；环境名含 `=`；环境值含 NUL；`describe` 不含参数值/环境值。

---

## 14. XNull 伪代码

```xnull
class CommandLine {
    final String _program
    final List<String> _arguments
    final String? _workingDirectory
    final Map<String, String> _environment

    CommandLine(String program, List<String> arguments) {
        if program == null || program == "" {
            throw "CommandLine: empty program"
        }
        if program.indexOf("\0") >= 0 {
            throw "CommandLine: NUL in program"
        }
        if arguments == null {
            throw "CommandLine: null arguments"
        }
        List<String> copiedArguments = arguments.copy()
        Int index = 0
        while index < copiedArguments.length() {
            String value = copiedArguments.get(index)
            if value == null {
                throw "CommandLine: null argument"
            }
            if value.indexOf("\0") >= 0 {
                throw "CommandLine: NUL in argument"
            }
            index = index + 1
        }
        _program = program
        _arguments = copiedArguments
        _workingDirectory = null
        _environment = [:]
    }

    private CommandLine(String program, List<String> arguments, String? workingDirectory,
                        Map<String, String> environment) {
        if program == null || program == "" {
            throw "CommandLine: empty program"
        }
        if program.indexOf("\0") >= 0 {
            throw "CommandLine: NUL in program"
        }
        if arguments == null || environment == null {
            throw "CommandLine: null field"
        }
        if workingDirectory != null {
            String directory = workingDirectory as String
            if directory == "" || directory.indexOf("\0") >= 0 {
                throw "CommandLine: invalid working directory"
            }
        }
        List<String> copiedArguments = arguments.copy()
        Int argumentIndex = 0
        while argumentIndex < copiedArguments.length() {
            String value = copiedArguments.get(argumentIndex)
            if value == null || value.indexOf("\0") >= 0 {
                throw "CommandLine: invalid argument"
            }
            argumentIndex = argumentIndex + 1
        }
        Map<String, String> copiedEnvironment = [:]
        List<String> keys = environment.keys()
        Int keyIndex = 0
        while keyIndex < keys.length() {
            String key = keys.get(keyIndex)
            if key == null || key == "" || key.indexOf("=") >= 0 || key.indexOf("\0") >= 0 {
                throw "CommandLine: invalid environment name"
            }
            String? environmentValue = environment.getOr(key, null)
            if environmentValue == null || environmentValue.indexOf("\0") >= 0 {
                throw "CommandLine: invalid environment value"
            }
            copiedEnvironment.put(key, environmentValue as String)
            keyIndex = keyIndex + 1
        }
        _program = program
        _arguments = copiedArguments
        _workingDirectory = workingDirectory
        _environment = copiedEnvironment
    }

    static CommandLine of(String program) {
        return new CommandLine(program, [])
    }

    static CommandLine fromArgv(List<String> tokens) {
        if tokens == null || tokens.length() == 0 {
            throw "CommandLine.fromArgv: empty tokens"
        }
        String program = tokens.get(0)
        List<String> arguments = []
        Int index = 1
        while index < tokens.length() {
            arguments.push(tokens.get(index))
            index = index + 1
        }
        return new CommandLine(program, arguments)
    }

    String program() { return _program }
    List<String> arguments() { return _arguments.copy() }
    Int argumentCount() { return _arguments.length() }
    String? workingDirectory() { return _workingDirectory }

    Map<String, String> environment() { return _environment.copy() }

    List<String> argv() {
        List<String> result = [_program]
        Int index = 0
        while index < _arguments.length() {
            result.push(_arguments.get(index))
            index = index + 1
        }
        return result
    }

    CommandLine withArgument(String value) {
        if value == null || value.indexOf("\0") >= 0 {
            throw "CommandLine.withArgument: invalid argument"
        }
        List<String> arguments = _arguments.copy()
        arguments.push(value)
        return new CommandLine(_program, arguments, _workingDirectory, _environment)
    }

    CommandLine withArguments(List<String> values) {
        if values == null {
            throw "CommandLine.withArguments: null values"
        }
        return new CommandLine(_program, values, _workingDirectory, _environment)
    }

    CommandLine withWorkingDirectory(String path) {
        if path == null || path == "" || path.indexOf("\0") >= 0 {
            throw "CommandLine.withWorkingDirectory: invalid path"
        }
        return new CommandLine(_program, _arguments, path, _environment)
    }

    CommandLine withoutWorkingDirectory() {
        return new CommandLine(_program, _arguments, null, _environment)
    }

    CommandLine withEnvironment(String name, String value) {
        if name == null || name == "" || name.indexOf("=") >= 0 || name.indexOf("\0") >= 0 {
            throw "CommandLine.withEnvironment: invalid name"
        }
        if value == null || value.indexOf("\0") >= 0 {
            throw "CommandLine.withEnvironment: invalid value"
        }
        Map<String, String> environment = _environment.copy()
        environment.put(name, value)
        return new CommandLine(_program, _arguments, _workingDirectory, environment)
    }

    CommandLine withEnvironmentAll(Map<String, String> values) {
        if values == null {
            throw "CommandLine.withEnvironmentAll: null values"
        }
        Map<String, String> environment = _environment.copy()
        List<String> keys = values.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if key == null || key == "" || key.indexOf("=") >= 0 || key.indexOf("\0") >= 0 {
                throw "CommandLine.withEnvironmentAll: invalid name"
            }
            String? value = values.getOr(key, null)
            if value == null || value.indexOf("\0") >= 0 {
                throw "CommandLine.withEnvironmentAll: invalid value"
            }
            environment.put(key, value as String)
            index = index + 1
        }
        return new CommandLine(_program, _arguments, _workingDirectory, environment)
    }

    String describe() {
        String directory = "process"
        if _workingDirectory != null {
            directory = _workingDirectory as String
        }
        return _program + " (" + str(_arguments.length()) + " arguments, "
            + str(_environment.length()) + " environment overrides, cwd=" + directory + ")"
    }
}
```
