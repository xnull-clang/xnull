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

    Bool has(String flag) {
        Int i = 0
        while i < self.raw.length() {
            if matchesFlag(self.raw.get(i), flag) {
                return true
            }
            i = i + 1
        }
        return false
    }

    String value(String flag) {
        String prefix = flag + "="
        String result = ""
        Bool found = false
        Int i = 0
        while i < self.raw.length() {
            String arg = self.raw.get(i)
            if !found && arg == flag {
                if i + 1 < self.raw.length() {
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

    String valueOr(String flag, String fallback) {
        String v = self.value(flag)
        if v == "" {
            return fallback
        }
        return v
    }

    List<String> positionals() {
        List<String> res = []
        Bool skipNext = false
        Int i = 0
        while i < self.raw.length() {
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
        return res
    }
}

class OptionSpec {
    final String name
    final Bool takesValue
    final String help
    final Bool required

    OptionSpec(String name, Bool takesValue, String help, Bool required) {
        self.name = name
        self.takesValue = takesValue
        self.help = help
        self.required = required
    }
}

class CommandMatch {
    final Args arguments
    final String command

    CommandMatch(Args arguments, String command) {
        self.arguments = arguments
        self.command = command
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

    Command(String name, String summary, List<OptionSpec> options) {
        self.name = name
        self.summary = summary
        self.options = options
        self.subcommands = []
    }

    Void add(Command child) {
        self.subcommands.push(child)
    }

    List<Command> children() {
        return self.subcommands
    }

    Result<CommandMatch, Error> parse(Args arguments) {
        if self.subcommands.length() > 0 {
            List<String> positional = arguments.positionals()
            if positional.length() > 0 {
                String first = positional.get(0)
                Int childIndex = 0
                while childIndex < self.subcommands.length() {
                    Command child = self.subcommands.get(childIndex)
                    if child.name == first {
                        List<String> rest = []
                        Int argIndex = 0
                        while argIndex < arguments.length() {
                            String argument = arguments.get(argIndex)
                            if argument != first {
                                rest.push(argument)
                            }
                            argIndex = argIndex + 1
                        }
                        return child.parse(new Args(rest))
                    }
                    childIndex = childIndex + 1
                }
                return Err(cliError(ErrorKind.InvalidArgument, "unknown command: " + first))
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

        Int argumentIndex = 0
        while argumentIndex < arguments.length() {
            String argument = arguments.get(argumentIndex)
            if isOption(argument) && !isKnownOption(argument, self.options) {
                return Err(cliError(ErrorKind.InvalidArgument, "unknown option: " + argument))
            }
            argumentIndex = argumentIndex + 1
        }
        return Ok(new CommandMatch(arguments, self.name))
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
