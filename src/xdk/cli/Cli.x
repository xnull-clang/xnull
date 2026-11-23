// Tier: T0；依赖：xdk.text、xdk.sys；稳定性：preview。
// xdk.cli —— 命令行解析与用法（W5）
//
// 面：参数列表、flag/值查询（`--k v` 与 `--k=v`）、位置参数、usage 文本、
// 退出码映射。子命令与帮助渲染为后续切片。
package xdk.cli
import xdk.errors

static Error cliError(ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error
}

static Bool isOption(String arg) {
    return arg.length() > 0 && arg.substring(0, 1) == "-"
}

static Bool matchesFlag(String arg, String flag) {
    return arg == flag || arg.startsWith(flag + "=")
}

static Bool isShortCluster(String arg) {
    return arg.length() > 2 && arg.substring(0, 1) == "-" && arg.substring(0, 2) != "--"
}

static Bool shortClusterKnown(String arg, List<String> knownShortFlags) {
    Int i = 1
    while i < arg.length() {
        String candidate = "-" + arg.substring(i, 1)
        Bool found = false
        Int k = 0
        while k < knownShortFlags.length() {
            if knownShortFlags.get(k) == candidate {
                found = true
            }
            k = k + 1
        }
        if !found {
            return false
        }
        i = i + 1
    }
    return true
}

class Args {
    List<String> raw

    Args(List<String> raw) {
        self.raw = raw
    }

    Int length() {
        return self.raw.length()
    }

    String get(Int i) {
        return self.raw.get(i)
    }

    // `--` 之后全部按位置参数处理；返回 -1 表示没有终止符。
    Int terminatorIndex() {
        Int i = 0
        while i < self.raw.length() {
            if self.raw.get(i) == "--" {
                return i
            }
            i = i + 1
        }
        return -1
    }

    Int optionLimit() {
        Int terminator = self.terminatorIndex()
        if terminator < 0 {
            return self.raw.length()
        }
        return terminator
    }

    Bool has(String flag) {
        Int limit = self.optionLimit()
        Int i = 0
        while i < limit {
            if matchesFlag(self.raw.get(i), flag) {
                return true
            }
            i = i + 1
        }
        return false
    }

    @Deprecated
    String value(String flag) {
        String prefix = flag + "="
        String result = ""
        Bool found = false
        Int limit = self.optionLimit()
        Int i = 0
        while i < limit {
            String arg = self.raw.get(i)
            if !found && arg == flag {
                if i + 1 < limit {
                    result = self.raw.get(i + 1)
                }
                found = true
            }
            if !found && arg.startsWith(prefix) {
                result = arg.substring(prefix.length(), arg.length() - prefix.length())
                found = true
            }
            i = i + 1
        }
        return result
    }

    // 重复选项策略：value 取首次；lastValue 取末次；values 返回全部。
    String lastValue(String flag) {
        String prefix = flag + "="
        String result = ""
        Int limit = self.optionLimit()
        Int i = 0
        while i < limit {
            String arg = self.raw.get(i)
            if arg == flag {
                if i + 1 < limit {
                    result = self.raw.get(i + 1)
                }
            } else if arg.startsWith(prefix) {
                result = arg.substring(prefix.length(), arg.length() - prefix.length())
            }
            i = i + 1
        }
        return result
    }

    List<String> values(String flag) {
        String prefix = flag + "="
        List<String> result = []
        Int limit = self.optionLimit()
        Int i = 0
        while i < limit {
            String arg = self.raw.get(i)
            if arg == flag {
                if i + 1 < limit {
                    result.push(self.raw.get(i + 1))
                }
            } else if arg.startsWith(prefix) {
                result.push(arg.substring(prefix.length(), arg.length() - prefix.length()))
            }
            i = i + 1
        }
        return result
    }

    String valueOr(String flag, String fallback) {
        String v = self.value(flag)
        if v == "" {
            return fallback
        }
        return v
    }

    List<String> positionals() {
        List<String> res = []
        Int limit = self.optionLimit()
        Bool skipNext = false
        Int i = 0
        while i < limit {
            String arg = self.raw.get(i)
            if skipNext {
                skipNext = false
            } else if isOption(arg) {
                if arg.indexOf("=") < 0 {
                    skipNext = true
                }
            } else {
                res.push(arg)
            }
            i = i + 1
        }
        // `--` 之后不再解释 option，逐项作为位置参数。
        Int terminator = self.terminatorIndex()
        if terminator >= 0 {
            i = terminator + 1
            while i < self.raw.length() {
                res.push(self.raw.get(i))
                i = i + 1
            }
        }
        return res
    }

    // 把 `-abc` 展开为 `-a -b -c`，仅当每个短选项都在 knownShortFlags 中；
    // 否则原样保留（由上层按未知选项处理）。`--` 之后不展开。
    Args expandShortFlags(List<String> knownShortFlags) {
        List<String> result = []
        Int limit = self.optionLimit()
        Int i = 0
        while i < self.raw.length() {
            String arg = self.raw.get(i)
            if i < limit && isShortCluster(arg) && shortClusterKnown(arg, knownShortFlags) {
                Int k = 1
                while k < arg.length() {
                    result.push("-" + arg.substring(k, 1))
                    k = k + 1
                }
            } else {
                result.push(arg)
            }
            i = i + 1
        }
        return new Args(result)
    }
}

class OptionSpec {
    final String name
    final Bool takesValue
    final String help
    final Bool required
    String shortName

    OptionSpec(String name, Bool takesValue, String help, Bool required) {
        self.name = name
        self.takesValue = takesValue
        self.help = help
        self.required = required
        self.shortName = ""
    }

    OptionSpec withShort(String shortName) {
        OptionSpec spec = new OptionSpec(self.name, self.takesValue, self.help, self.required)
        spec.shortName = shortName
        return spec
    }
}

class ArgSpec {
    final String name
    final String help
    final Bool required

    ArgSpec(String name, String help, Bool required) {
        if name == null || name == "" {
            throw "ArgSpec: name must not be empty"
        }
        self.name = name
        self.help = help
        self.required = required
    }

    String describe() {
        if self.required {
            return "<" + self.name + ">"
        }
        return "[" + self.name + "]"
    }
}

class CommandMatch {
    final Args arguments
    final String command
    final List<String> _positionals

    CommandMatch(Args arguments, String command) {
        self.arguments = arguments
        self.command = command
        self._positionals = []
    }

    CommandMatch(Args arguments, String command, List<String> positionals) {
        self.arguments = arguments
        self.command = command
        self._positionals = positionals.copy()
    }

    List<String> positionals() {
        return self._positionals.copy()
    }
}

Bool isKnownOption(String argument, List<OptionSpec> options) {
    Int index = 0
    while index < options.length() {
        OptionSpec option = options.get(index)
        if argument == option.name || argument.startsWith(option.name + "=") {
            return true
        }
        index = index + 1
    }
    return false
}

class Command {
    final String name
    final String summary
    final List<OptionSpec> options
    final List<Command> subcommands
    final List<ArgSpec> _positionals

    Command(String name, String summary, List<OptionSpec> options) {
        self.name = name
        self.summary = summary
        self.options = options
        self.subcommands = []
        self._positionals = []
    }

    Void add(Command child) {
        self.subcommands.push(child)
    }

    Void addPositional(ArgSpec spec) {
        if spec == null {
            throw "Command.addPositional: null spec"
        }
        self._positionals.push(spec)
    }

    List<ArgSpec> positionals() {
        return self._positionals.copy()
    }

    List<String> positionalHelp() {
        List<String> result = []
        Int index = 0
        while index < self._positionals.length() {
            ArgSpec spec = self._positionals.get(index)
            String line = spec.name + ": " + spec.help
            if spec.required {
                line = line + " (required)"
            }
            result.push(line)
            index = index + 1
        }
        return result
    }

    List<Command> children() {
        return self.subcommands
    }

    List<String> shortNames() {
        List<String> result = []
        Int index = 0
        while index < self.options.length() {
            String shortName = self.options.get(index).shortName
            if shortName.length() > 0 {
                result.push(shortName)
            }
            index = index + 1
        }
        return result
    }

    String longForShort(String shortName) {
        Int index = 0
        while index < self.options.length() {
            OptionSpec option = self.options.get(index)
            if option.shortName == shortName {
                return option.name
            }
            index = index + 1
        }
        return ""
    }

    Bool takesValueFor(String longName) {
        Int index = 0
        while index < self.options.length() {
            OptionSpec option = self.options.get(index)
            if option.name == longName {
                return option.takesValue
            }
            index = index + 1
        }
        return false
    }

    // 仅合并“全部是 flag”的短选项簇；含取值选项时留给上层报未知选项。
    List<String> expandCluster(String arg) {
        List<String> result = []
        Int index = 1
        while index < arg.length() {
            String longName = self.longForShort("-" + arg.substring(index, 1))
            if longName == "" || self.takesValueFor(longName) {
                List<String> empty = []
                return empty
            }
            result.push(longName)
            index = index + 1
        }
        return result
    }

    Args normalize(Args arguments) {
        List<String> result = []
        Int limit = arguments.terminatorIndex()
        Int index = 0
        while index < arguments.length() {
            String arg = arguments.get(index)
            if limit >= 0 && index >= limit {
                result.push(arg)
            } else if self.longForShort(arg) != "" {
                result.push(self.longForShort(arg))
            } else if isShortCluster(arg) {
                List<String> expanded = self.expandCluster(arg)
                if expanded.length() > 0 {
                    Int item = 0
                    while item < expanded.length() {
                        result.push(expanded.get(item))
                        item = item + 1
                    }
                } else {
                    result.push(arg)
                }
            } else {
                result.push(arg)
            }
            index = index + 1
        }
        return new Args(result)
    }

    OptionSpec? findOption(String argument, Bool deep) {
        Int index = 0
        while index < self.options.length() {
            OptionSpec option = self.options.get(index)
            if argument == option.name || argument.startsWith(option.name + "=") {
                return option
            }
            if option.shortName.length() > 0 {
                if argument == option.shortName || argument.startsWith(option.shortName + "=") {
                    return option
                }
            }
            index = index + 1
        }
        if deep {
            Int childIndex = 0
            while childIndex < self.subcommands.length() {
                OptionSpec? found = self.subcommands.get(childIndex).findOption(argument, true)
                if found != null {
                    return found
                }
                childIndex = childIndex + 1
            }
        }
        return null
    }

    Result<CommandMatch, Error> parse(Args arguments) {
        arguments = self.normalize(arguments)
        if self.subcommands.length() > 0 {
            Int scanIndex = 0
            while scanIndex < arguments.length() {
                String argument = arguments.get(scanIndex)
                if argument == "--" {
                    break
                }
                if isOption(argument) {
                    OptionSpec? option = self.findOption(argument, true)
                    if option == null {
                        return Err(cliError(ErrorKind.InvalidArgument, "unknown option: " + argument))
                    }
                    OptionSpec found = option as OptionSpec
                    if found.takesValue && argument.indexOf("=") < 0 {
                        if scanIndex + 1 >= arguments.length() || arguments.get(scanIndex + 1) == "--" {
                            return Err(cliError(ErrorKind.InvalidArgument, "missing value for option: " + found.name))
                        }
                        scanIndex = scanIndex + 2
                    } else {
                        scanIndex = scanIndex + 1
                    }
                    continue
                }
                Int childIndex = 0
                while childIndex < self.subcommands.length() {
                    Command child = self.subcommands.get(childIndex)
                    if child.name == argument {
                        List<String> rest = []
                        Int argIndex = 0
                        while argIndex < arguments.length() {
                            if argIndex != scanIndex {
                                rest.push(arguments.get(argIndex))
                            }
                            argIndex = argIndex + 1
                        }
                        return child.parse(new Args(rest))
                    }
                    childIndex = childIndex + 1
                }
                return Err(cliError(ErrorKind.InvalidArgument, "unknown command: " + argument))
            }
        }

        Int optionIndex = 0
        while optionIndex < self.options.length() {
            OptionSpec option = self.options.get(optionIndex)
            if option.required && !arguments.has(option.name) {
                return Err(cliError(ErrorKind.InvalidArgument, "missing required option: " + option.name))
            }
            if option.takesValue && arguments.has(option.name) && arguments.value(option.name) == "" {
                return Err(cliError(ErrorKind.InvalidArgument, "missing value for option: " + option.name))
            }
            optionIndex = optionIndex + 1
        }

        List<String> values = []
        Bool afterTerminator = false
        Int argumentIndex = 0
        while argumentIndex < arguments.length() {
            String argument = arguments.get(argumentIndex)
            if afterTerminator {
                values.push(argument)
                argumentIndex = argumentIndex + 1
                continue
            }
            if argument == "--" {
                afterTerminator = true
                argumentIndex = argumentIndex + 1
                continue
            }
            if isOption(argument) {
                OptionSpec? option = self.findOption(argument, false)
                if option == null {
                    return Err(cliError(ErrorKind.InvalidArgument, "unknown option: " + argument))
                }
                OptionSpec found = option as OptionSpec
                if found.takesValue && argument.indexOf("=") < 0 {
                    if argumentIndex + 1 >= arguments.length() || arguments.get(argumentIndex + 1) == "--" {
                        return Err(cliError(ErrorKind.InvalidArgument, "missing value for option: " + found.name))
                    }
                    argumentIndex = argumentIndex + 2
                } else {
                    argumentIndex = argumentIndex + 1
                }
                continue
            }
            values.push(argument)
            argumentIndex = argumentIndex + 1
        }

        Int specIndex = 0
        while specIndex < self._positionals.length() {
            if specIndex >= values.length() {
                ArgSpec spec = self._positionals.get(specIndex)
                if spec.required {
                    return Err(cliError(ErrorKind.InvalidArgument, "missing required argument: " + spec.name))
                }
            }
            specIndex = specIndex + 1
        }
        if values.length() > self._positionals.length() {
            return Err(cliError(ErrorKind.InvalidArgument,
                "too many positional arguments: expected " + str(self._positionals.length()) +
                ", got " + str(values.length())))
        }
        return Ok(new CommandMatch(arguments, self.name, values))
    }

    String help() {
        String text = "usage: " + self.name
        Int optionIndex = 0
        while optionIndex < self.options.length() {
            OptionSpec option = self.options.get(optionIndex)
            if option.takesValue {
                text = text + " " + option.name + " <value>"
            } else {
                text = text + " [" + option.name + "]"
            }
            optionIndex = optionIndex + 1
        }
        Int positionalIndex = 0
        while positionalIndex < self._positionals.length() {
            text = text + " " + self._positionals.get(positionalIndex).describe()
            positionalIndex = positionalIndex + 1
        }
        text = text + "\n" + self.summary + "\noptions:"
        optionIndex = 0
        while optionIndex < self.options.length() {
            OptionSpec option = self.options.get(optionIndex)
            text = text + "\n  " + option.name + "  " + option.help
            if option.required {
                text = text + " (required)"
            }
            optionIndex = optionIndex + 1
        }
        if self._positionals.length() > 0 {
            text = text + "\narguments:"
            positionalIndex = 0
            while positionalIndex < self._positionals.length() {
                ArgSpec spec = self._positionals.get(positionalIndex)
                text = text + "\n  " + spec.describe() + "  " + spec.help
                positionalIndex = positionalIndex + 1
            }
        }
        if self.subcommands.length() > 0 {
            text = text + "\ncommands:"
            Int childIndex = 0
            while childIndex < self.subcommands.length() {
                Command child = self.subcommands.get(childIndex)
                text = text + "\n  " + child.name + "  " + child.summary
                childIndex = childIndex + 1
            }
        }
        return text
    }
}

// ---------- 补全（T0-X） ----------

static String completionWords(Command command) {
    String words = ""
    Int index = 0
    while index < command.options.length() {
        OptionSpec option = command.options.get(index)
        if words.length() > 0 {
            words = words + " "
        }
        words = words + option.name
        if option.shortName.length() > 0 {
            words = words + " " + option.shortName
        }
        index = index + 1
    }
    index = 0
    while index < command.subcommands.length() {
        if words.length() > 0 {
            words = words + " "
        }
        words = words + command.subcommands.get(index).name
        index = index + 1
    }
    if words.length() > 0 {
        words = words + " "
    }
    words = words + "help"
    return words
}

// 生成 bash `complete -W` 文本：根命令一行，每个直接子命令一行。
String completionBash(Command root) {
    String text = "complete -W \"" + completionWords(root) + "\" " + root.name
    Int index = 0
    while index < root.subcommands.length() {
        Command child = root.subcommands.get(index)
        text = text + "\ncomplete -W \"" + completionWords(child) + "\" \"" +
            root.name + " " + child.name + "\""
        index = index + 1
    }
    return text
}

// ---------- 默认值优先级（T0-X） ----------
// argv > 环境变量 > 配置值 > fallback；空配置值视为未提供。

String defaultFromEnv(String envName, String fallback) {
    if envName.length() > 0 && envHasRaw(envName) != 0 {
        return envRaw(envName)
    }
    return fallback
}

String resolveValue(Args arguments, String flag, String envName, String configValue, String fallback) {
    if arguments.has(flag) {
        return arguments.value(flag)
    }
    if envName.length() > 0 && envHasRaw(envName) != 0 {
        return envRaw(envName)
    }
    if configValue.length() > 0 {
        return configValue
    }
    return fallback
}

String usage(String program, String summary) {
    return "usage: " + program + " " + summary
}

Int exitCodeFor(String outcome) {
    if outcome == "ok" {
        return 0
    }
    if outcome == "usage" {
        return 2
    }
    return 1
}
