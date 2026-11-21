# `Parser`

| 项 | 值 |
| --- | --- |
| 类型 | `class Parser` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `Command`、`OptionSpec`、`ParseResult`、`Args`、`UsageError`、`ValueParser` |

---

## 1. 定位

把 argv 按 `Command` 树解析为 `ParseResult`：长/短选项、`--` 终止符、子命令、默认值、必填、重复策略、值解析。

不做：执行命令、打印 help/usage、读写环境、进程退出、shell 补全。

---

## 2. 设计逻辑

- 单次线性扫描；不修改 argv。
- 选项在“当前命令到根的路径”上查找；祖先选项在子命令后仍可用。
- 同一路径上重复的长名/短名在进入子命令时拒绝，避免值 Map 冲突。
- 长选项：`--name value`、`--name=value`；短选项：`-n value`、`-n=value`；不支持 `-abc` 合并。
- flag 不接受值；`--flag=value` 报错。
- 值选项的下一个 token 无条件作为值消费；仅 `--` 视为缺值。
- 重复选项默认报错；`repeatable` 时值累积，flag 次数累积。
- 子命令：当前命令有子命令时，普通 token 必须是子命令名/别名；叶命令才收集位置参数。
- `--` 后不再识别选项或子命令；余下全部位置参数。
- 必填在扫描结束后检查；默认值只补值，不伪造 occurrence。
- 所有用户输入错误返回 `UsageError`；null 参数是合同错误。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_root` | `Command` | 根命令 |

不变量：root 非 null；parser 不修改 command 树。

---

## 4. 生命周期

构造后复用；无 close；可共享；线程安全（只读 command 树，局部解析状态）。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Parser(Command root)` | root | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 解析 argv | `List<String> arguments` | `Result<ParseResult, Error>` | `UsageError`；null → panic |
| `root` | 根命令 | 无 | `Command` | 无 |

内部方法：

| 方法 | 用途 | 失败 |
| --- | --- | --- |
| `findOption` | 沿路径查找选项 | 无（未找到 → null） |
| `checkPathOptions` | 路径选项重名检查 | `UsageError` |
| `recordOption` | 记录出现/值 | `UsageError` |
| `usageError` | 构造用法错误 | 无 |
| `joinPath` | 路径文本 | 无 |

关键行为：

- 未知长/短选项 → `UsageError`。
- 缺值 → `UsageError`。
- flag 带值 → `UsageError`。
- 重复且不可重复 → `UsageError`。
- `ValueParser` 失败 → `UsageError`，保留其 describe。
- 未知子命令 → `UsageError`。
- 缺必填选项/必选子命令 → `UsageError`。
- 默认值只在缺失时补入 `ParseResult.values`；不增加 `hasOption`。

---

## 8. 使用的技术

- 线性扫描；
- 路径查找；
- 选项状态机；
- Map 累积；
- 默认值/必填检查；
- 错误包装。

---

## 9. 需要的支撑

- 语言：class、List、Map、String、Bool、Int、Result；
- 运行时：无；
- 接口：`Command`、`OptionSpec`、`ParseResult`、`Args`、`UsageError`、`ValueParser`、`isOptionToken`。

---

## 10. 依赖的特性/接口/类

`Command`、`OptionSpec`、`ParseResult`、`Args`、`UsageError`、`ValueParser`、`isOptionToken`。

---

## 11. 所有权与并发

只读 `_root`；每次 parse 使用局部 Map/List；可并发调用；不共享可变解析状态。

---

## 12. 示例与反例

正确：`new Parser(app).parse(["--output","a","build","--release","src"])`。  
反例：期望 `-abc` 合并；期望未知选项被忽略；期望 `--help` 自动生效；期望 flag 有值。

---

## 13. 测试/场景义务

长/短选项；`=`；缺值；flag 带值；重复/可重复；默认值；必填；子命令；别名；祖先选项；路径重名；`--`；负数；未知选项/命令；值解析失败；空 argv。

---

## 14. XNull 伪代码

```xnull
class Parser {
    final Command _root

    Parser(Command root) {
        if root == null { throw "Parser: null root" }
        _root = root
    }

    Command root() { return _root }

    Result<ParseResult, Error> parse(List<String> arguments) {
        if arguments == null { throw "Parser.parse: null arguments" }
        Command current = _root
        List<Command> path = [_root]
        List<String> pathNames = [_root.name()]
        List<String> positionals = []
        Map<String, Int> occurrences = [:]
        Map<String, List<String>> values = [:]
        List<String> optionOrder = []
        Bool endOfOptions = false
        Int index = 0
        while index < arguments.length() {
            String token = arguments.get(index)
            if !endOfOptions && token == "--" {
                endOfOptions = true
                index = index + 1
                continue
            }
            if !endOfOptions && isOptionToken(token) {
                OptionSpec? spec = null
                String? inlineValue = null
                String parsedName = ""
                if token.startsWith("--") {
                    Int equals = token.indexOf("=")
                    if equals >= 0 {
                        parsedName = token.substring(2, equals - 2)
                        inlineValue = token.substring(equals + 1, token.length() - equals - 1)
                    } else {
                        parsedName = token.substring(2, token.length() - 2)
                    }
                    spec = self.findOption(path, parsedName, false)
                    if spec == null {
                        return Err(self.usageError("unknown option --" + parsedName, "--" + parsedName, pathNames))
                    }
                } else {
                    Int equals = token.indexOf("=")
                    if equals >= 0 {
                        parsedName = token.substring(1, equals - 1)
                        inlineValue = token.substring(equals + 1, token.length() - equals - 1)
                    } else if token.length() == 2 {
                        parsedName = token.substring(1, 1)
                    } else {
                        return Err(self.usageError("combined short options are not supported: " + token, null, pathNames))
                    }
                    spec = self.findOption(path, parsedName, true)
                    if spec == null {
                        return Err(self.usageError("unknown option -" + parsedName, "-" + parsedName, pathNames))
                    }
                }
                OptionSpec option = spec as OptionSpec
                String? value = null
                if option.hasValue() {
                    if inlineValue != null {
                        value = inlineValue
                    } else {
                        if index + 1 >= arguments.length() {
                            return Err(self.usageError("missing value for " + option.longToken(), option.longToken(), pathNames))
                        }
                        String next = arguments.get(index + 1)
                        if next == "--" {
                            return Err(self.usageError("missing value for " + option.longToken(), option.longToken(), pathNames))
                        }
                        value = next
                        index = index + 1
                    }
                    ValueParser? parser = option.valueParser()
                    if parser != null {
                        String rawValue = value as String
                        Result<String, Error> parsed = parser.parse(rawValue)
                        if parsed.isErr() {
                            return Err(self.usageError(
                                "invalid value for " + option.longToken() + ": " + parsed.error().describe(),
                                option.longToken(), pathNames))
                        }
                        value = parsed.value()
                    }
                } else if inlineValue != null {
                    return Err(self.usageError("option does not take a value: " + option.longToken(), option.longToken(), pathNames))
                }
                Result<Unit, Error> recorded = self.recordOption(
                    option, value, occurrences, values, optionOrder, pathNames)
                if recorded.isErr() { return Err(recorded.error()) }
                index = index + 1
                continue
            }
            if !endOfOptions && current.hasSubcommands() {
                Command? child = current.findSubcommand(token)
                if child == null {
                    return Err(self.usageError("unknown command: " + token, null, pathNames))
                }
                current = child
                path.push(child)
                pathNames.push(child.name())
                Result<Unit, Error> checked = self.checkPathOptions(path, pathNames)
                if checked.isErr() { return Err(checked.error()) }
                index = index + 1
                continue
            }
            positionals.push(token)
            index = index + 1
        }
        if current.requiresSubcommand() {
            return Err(self.usageError("missing subcommand", null, pathNames))
        }
        Map<String, OptionSpec> specs = [:]
        Int pathIndex = 0
        while pathIndex < path.length() {
            List<OptionSpec> options = path.get(pathIndex).options()
            Int optionIndex = 0
            while optionIndex < options.length() {
                OptionSpec spec = options.get(optionIndex)
                specs.put(spec.name(), spec)
                if !occurrences.has(spec.name()) {
                    String? defaultValue = spec.defaultValue()
                    if defaultValue != null {
                        List<String> defaultValues = [defaultValue as String]
                        values.put(spec.name(), defaultValues)
                    } else if spec.isRequired() {
                        return Err(self.usageError(
                            "missing required option " + spec.longToken(), spec.longToken(), pathNames))
                    }
                }
                optionIndex = optionIndex + 1
            }
            pathIndex = pathIndex + 1
        }
        return Ok(new ParseResult(
            current, pathNames, new Args(arguments), positionals,
            occurrences, values, optionOrder, specs))
    }

    OptionSpec? findOption(List<Command> path, String name, Bool useShortName) {
        Int index = path.length() - 1
        while index >= 0 {
            Command command = path.get(index)
            OptionSpec? found = null
            if useShortName {
                found = command.findOptionByShort(name)
            } else {
                found = command.findOption(name)
            }
            if found != null { return found }
            index = index - 1
        }
        return null
    }

    Result<Unit, Error> checkPathOptions(List<Command> path, List<String> pathNames) {
        Map<String, String> longNames = [:]
        Map<String, String> shortNames = [:]
        Int pathIndex = 0
        while pathIndex < path.length() {
            Command command = path.get(pathIndex)
            List<OptionSpec> options = command.options()
            Int optionIndex = 0
            while optionIndex < options.length() {
                OptionSpec option = options.get(optionIndex)
                if longNames.has(option.name()) {
                    return Err(self.usageError(
                        "duplicate option on command path: " + option.longToken(),
                        option.longToken(), pathNames))
                }
                longNames.put(option.name(), command.name())
                String? shortName = option.shortName()
                if shortName != null {
                    String shortValue = shortName as String
                    if shortNames.has(shortValue) {
                        return Err(self.usageError(
                            "duplicate short option on command path: -" + shortValue,
                            "-" + shortValue, pathNames))
                    }
                    shortNames.put(shortValue, command.name())
                }
                optionIndex = optionIndex + 1
            }
            pathIndex = pathIndex + 1
        }
        return Ok(unit)
    }

    Result<Unit, Error> recordOption(OptionSpec spec, String? value,
            Map<String, Int> occurrences, Map<String, List<String>> values,
            List<String> optionOrder, List<String> pathNames) {
        Int count = 0
        if occurrences.has(spec.name()) {
            count = occurrences.getOr(spec.name(), 0)
        }
        if count > 0 && !spec.isRepeatable() {
            return Err(self.usageError(
                "option repeated: " + spec.longToken(), spec.longToken(), pathNames))
        }
        occurrences.put(spec.name(), count + 1)
        if count == 0 { optionOrder.push(spec.name()) }
        if spec.hasValue() {
            if value == null {
                return Err(self.usageError(
                    "missing value for " + spec.longToken(), spec.longToken(), pathNames))
            }
            List<String> currentValues = []
            if values.has(spec.name()) {
                currentValues = values.getOr(spec.name(), []).copy()
            }
            currentValues.push(value as String)
            values.put(spec.name(), currentValues)
        } else if value != null {
            return Err(self.usageError(
                "option does not take a value: " + spec.longToken(), spec.longToken(), pathNames))
        }
        return Ok(unit)
    }

    UsageError usageError(String message, String? optionToken, List<String> pathNames) {
        UsageError error = new UsageError(message)
        if optionToken != null {
            String token = optionToken as String
            if isOptionToken(token) {
                error = error.withOption(token)
            }
        }
        if pathNames.length() > 0 {
            error = error.withCommandPath(self.joinPath(pathNames))
        }
        return error.withShowUsage(true)
    }

    String joinPath(List<String> pathNames) {
        String result = ""
        Int index = 0
        while index < pathNames.length() {
            if index > 0 { result = result + " " }
            result = result + pathNames.get(index)
            index = index + 1
        }
        return result
    }
}
```
