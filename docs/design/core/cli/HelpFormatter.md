# `HelpFormatter`

| 项 | 值 |
| --- | --- |
| 类型 | `class HelpFormatter` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `Command`、`OptionSpec` |

---

## 1. 定位

把 `Command` 树渲染成 help/usage 文本：摘要、usage、描述、选项、子命令。

不做：写 stdout/stderr、终端宽度探测、颜色、分页、自动 help 触发、国际化。

---

## 2. 设计逻辑

- 无状态；所有方法只读 command 树。
- 固定布局：选项/子命令两列，左列宽 28。
- 隐藏选项/子命令不进入列表。
- `summary`/`description` 原样输出；不做自动换行。
- `usage` 只生成一行；`format` 组合完整 help。
- 不自动追加 `--help`；只有命令树里声明的选项才显示。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

无状态；可共享；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HelpFormatter()` | 无 | 无 | 无 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `format` | 完整 help | `Command command, String programPath` | `String` | null → panic |
| `usage` | 单行 usage | `Command command, String programPath` | `String` | null → panic |
| `options` | 选项段 | `Command command` | `String` | null → panic |
| `subcommands` | 子命令段 | `Command command` | `String` | null → panic |
| `width` | 左列宽度 | 无 | `Int` | 无 |

说明：

- `programPath` 为空时用 `command.name()`。
- `format` 返回的文本可能不含结尾换行；调用方决定如何打印。
- 隐藏项不显示；空选项/子命令段不生成标题。
- `width` 固定 28；仅用于格式化，不查询终端。

---

## 8. 使用的技术

- 字符串拼接；
- 列对齐；
- 树遍历（单层）；
- 隐藏过滤。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、List；
- 运行时：无；
- 接口：`Command`、`OptionSpec`。

---

## 10. 依赖的特性/接口/类

`Command`、`OptionSpec`。

---

## 11. 所有权与并发

无状态；可共享；无资源。

---

## 12. 示例与反例

正确：`new HelpFormatter().format(app, "app")`。  
反例：期望自动颜色/换行；期望隐藏选项仍显示；期望 `format` 直接打印。

---

## 13. 测试/场景义务

摘要/描述；usage；选项对齐；短名/值名/required；隐藏；子命令别名；空命令；`programPath` 空串。

---

## 14. XNull 伪代码

```xnull
class HelpFormatter {
    HelpFormatter() {
    }

    Int width() { return 28 }

    String format(Command command, String programPath) {
        if command == null || programPath == null {
            throw "HelpFormatter.format: null argument"
        }
        String path = programPath
        if path == "" { path = command.name() }
        String result = ""
        if command.summary() != "" {
            result = result + command.summary() + "\n\n"
        }
        result = result + self.usage(command, path) + "\n"
        if command.description() != "" {
            result = result + "\n" + command.description() + "\n"
        }
        String optionsText = self.options(command)
        if optionsText != "" {
            result = result + "\nOptions:\n" + optionsText
        }
        String commandsText = self.subcommands(command)
        if commandsText != "" {
            result = result + "\nCommands:\n" + commandsText
        }
        return result
    }

    String usage(Command command, String programPath) {
        if command == null || programPath == null {
            throw "HelpFormatter.usage: null argument"
        }
        String path = programPath
        if path == "" { path = command.name() }
        String result = "usage: " + path
        if self.options(command) != "" {
            result = result + " [options]"
        }
        if command.subcommands().length() > 0 {
            result = result + " <command>"
        } else {
            result = result + " [arguments]"
        }
        return result
    }

    String options(Command command) {
        if command == null { throw "HelpFormatter.options: null command" }
        String result = ""
        List<OptionSpec> options = command.options()
        Int index = 0
        while index < options.length() {
            OptionSpec spec = options.get(index)
            if !spec.isHidden() {
                String line = "  "
                String? shortName = spec.shortName()
                if shortName != null {
                    line = line + "-" + (shortName as String) + ", "
                }
                line = line + spec.longToken()
                if spec.hasValue() {
                    line = line + " <" + spec.valueName() + ">"
                }
                if spec.isRequired() {
                    line = line + " (required)"
                }
                line = self.padRight(line, self.width())
                if spec.description() != "" {
                    line = line + spec.description()
                }
                result = result + line + "\n"
            }
            index = index + 1
        }
        return result
    }

    String subcommands(Command command) {
        if command == null { throw "HelpFormatter.subcommands: null command" }
        String result = ""
        List<Command> subcommands = command.subcommands()
        Int index = 0
        while index < subcommands.length() {
            Command child = subcommands.get(index)
            if !child.isHidden() {
                String line = "  " + child.name()
                List<String> aliases = child.aliases()
                if aliases.length() > 0 {
                    line = line + " ("
                    Int aliasIndex = 0
                    while aliasIndex < aliases.length() {
                        if aliasIndex > 0 { line = line + ", " }
                        line = line + aliases.get(aliasIndex)
                        aliasIndex = aliasIndex + 1
                    }
                    line = line + ")"
                }
                line = self.padRight(line, self.width())
                if child.summary() != "" {
                    line = line + child.summary()
                }
                result = result + line + "\n"
            }
            index = index + 1
        }
        return result
    }

    String padRight(String text, Int width) {
        String result = text
        while result.length() < width {
            result = result + " "
        }
        return result
    }
}
```
