# `Command`

| 项 | 值 |
| --- | --- |
| 类型 | `class Command` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `OptionSpec` |

---

> 注解合同（A8，planned）：`@Value` 生成 `equals`/`hash`/`toString`/`copy`；列表字段按值语义比较/复制；字段保持 `final`。实现由处理器生成，不手写；实现时删除同名手写成员，避免生成冲突；伪代码中的 `equals`/`toString`/`copy` 只描述生成物行为。

## 1. 定位

命令树节点：命令名、别名、摘要、描述、选项、子命令、隐藏、是否必须选子命令。

不做：解析 argv、帮助布局、执行 handler、全局命令注册。

---

## 2. 设计逻辑

- 不可变；`with*` 返回新树节点，避免构建期被外部改坏。
- 命令名与别名使用 lower-kebab；不带前导 `-`。
- 同一命令内选项长名/短名唯一；子命令名/别名唯一。
- 子命令是 `Command` 列表；父节点不保存 parent，路径由 `Parser` 维护。
- 选项只在声明它的命令及后代可见；`Parser` 沿路径向上查找。
- 有子命令的节点不直接接受普通位置参数；`--` 后例外。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 命令名 |
| `_summary` | `String` | 一行摘要 |
| `_description` | `String` | 详细描述 |
| `_aliases` | `List<String>` | 别名 |
| `_options` | `List<OptionSpec>` | 本地选项 |
| `_subcommands` | `List<Command>` | 子命令 |
| `_isHidden` | `Bool` | help 中隐藏 |
| `_requireSubcommand` | `Bool` | 必须选择子命令 |

不变量：name/alias 合法；summary/description 非 null；aliases/options/subcommands 无重复；不可变。

---

## 4. 生命周期

不可变；无 close；可共享；线程安全。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Command(String name, String summary)` | name/summary | name 合法；summary 非 null | 非法 → panic |

派生方法对重复名/别名/短名 panic；不做静默覆盖。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 命令名 | 无 | `String` | 无 |
| `summary` | 摘要 | 无 | `String` | 无 |
| `description` | 描述 | 无 | `String` | 无 |
| `aliases` | 别名快照 | 无 | `List<String>` | 无 |
| `options` | 选项快照 | 无 | `List<OptionSpec>` | 无 |
| `subcommands` | 子命令快照 | 无 | `List<Command>` | 无 |
| `isHidden` | 是否隐藏 | 无 | `Bool` | 无 |
| `requiresSubcommand` | 是否必须选子命令 | 无 | `Bool` | 无 |
| `hasSubcommands` | 是否有子命令 | 无 | `Bool` | 无 |
| `withDescription` | 派生描述 | `String value` | `Command` | null → panic |
| `withAlias` | 派生别名 | `String alias` | `Command` | 非法/重复 → panic |
| `withOption` | 派生选项 | `OptionSpec option` | `Command` | null/重复 → panic |
| `withSubcommand` | 派生子命令 | `Command command` | `Command` | null/self/重复 → panic |
| `withHidden` | 派生隐藏 | `Bool value` | `Command` | 无 |
| `withRequireSubcommand` | 派生必选子命令 | `Bool value` | `Command` | 无 |
| `findOption` | 按长名查找 | `String name` | `OptionSpec?` | 无 |
| `findOptionByShort` | 按短名查找 | `String shortName` | `OptionSpec?` | 无 |
| `findSubcommand` | 按名/别名查找 | `String name` | `Command?` | 无 |

说明：

- 查找方法只查当前节点的直接子项，不递归；路径查找由 `Parser` 完成。
- `withOption` 同时检查长名与短名重复；`null` 短名不参与。
- `withSubcommand` 检查子命令名与所有别名，不与已有子命令冲突。
- `withAlias` 检查与命令名、已有别名冲突。
- `toString` 只返回命令名，便于诊断。

---

## 8. 使用的技术

- 不可变树；
- builder 派生；
- 列表快照；
- 名称唯一性检查。

---

## 9. 需要的支撑

- 语言：class、String、Bool、List；
- 运行时：无；
- 接口：`OptionSpec`、`isValidLongName`。

---

## 10. 依赖的特性/接口/类

`OptionSpec`、`isValidLongName`。

---

## 11. 所有权与并发

不可变；可共享；无资源；树节点可被多个 parser 共享。

---

## 12. 示例与反例

正确：`new Command("build","build project").withOption(release).withAlias("b")`。  
反例：命令名带 `--`；同一命令两个 `--output`；子命令名重复；解析后修改树。

---

## 13. 测试/场景义务

构造合法/非法；别名；选项重复；短名重复；子命令重复；查找；隐藏；必选子命令；派生独立性。

---

## 14. XNull 伪代码

```xnull
@Value
class Command {
    final String _name
    final String _summary
    final String _description
    final List<String> _aliases
    final List<OptionSpec> _options
    final List<Command> _subcommands
    final Bool _isHidden
    final Bool _requireSubcommand

    Command(String name, String summary) {
        if !isValidLongName(name) { throw "Command: invalid name" }
        if summary == null { throw "Command: null summary" }
        _name = name
        _summary = summary
        _description = ""
        _aliases = []
        _options = []
        _subcommands = []
        _isHidden = false
        _requireSubcommand = false
    }

    private Command(String name, String summary, String description, List<String> aliases,
                    List<OptionSpec> options, List<Command> subcommands,
                    Bool isHidden, Bool requireSubcommand) {
        if !isValidLongName(name) { throw "Command: invalid name" }
        if summary == null { throw "Command: null summary" }
        if description == null { throw "Command: null description" }
        if aliases == null || options == null || subcommands == null {
            throw "Command: null list"
        }
        _name = name
        _summary = summary
        _description = description
        _aliases = aliases.copy()
        _options = options.copy()
        _subcommands = subcommands.copy()
        _isHidden = isHidden
        _requireSubcommand = requireSubcommand
    }

    String name() { return _name }
    String summary() { return _summary }
    String description() { return _description }
    List<String> aliases() { return _aliases.copy() }
    List<OptionSpec> options() { return _options.copy() }
    List<Command> subcommands() { return _subcommands.copy() }
    Bool isHidden() { return _isHidden }
    Bool requiresSubcommand() { return _requireSubcommand }
    Bool hasSubcommands() { return _subcommands.length() > 0 }

    Command withDescription(String value) {
        if value == null { throw "Command.withDescription: null" }
        return new Command(_name, _summary, value, _aliases, _options, _subcommands, _isHidden, _requireSubcommand)
    }

    Command withAlias(String alias) {
        if alias == null || !isValidLongName(alias) { throw "Command.withAlias: invalid alias" }
        if alias == _name { throw "Command.withAlias: alias equals name" }
        Int index = 0
        while index < _aliases.length() {
            if _aliases.get(index) == alias { throw "Command.withAlias: duplicate alias" }
            index = index + 1
        }
        List<String> aliases = _aliases.copy()
        aliases.push(alias)
        return new Command(_name, _summary, _description, aliases, _options, _subcommands, _isHidden, _requireSubcommand)
    }

    Command withOption(OptionSpec option) {
        if option == null { throw "Command.withOption: null" }
        if self.findOption(option.name()) != null {
            throw "Command.withOption: duplicate option name"
        }
        String? shortName = option.shortName()
        if shortName != null {
            String shortValue = shortName as String
            if self.findOptionByShort(shortValue) != null {
                throw "Command.withOption: duplicate short name"
            }
        }
        List<OptionSpec> options = _options.copy()
        options.push(option)
        return new Command(_name, _summary, _description, _aliases, options, _subcommands, _isHidden, _requireSubcommand)
    }

    Command withSubcommand(Command command) {
        if command == null { throw "Command.withSubcommand: null" }
        if command == self { throw "Command.withSubcommand: self" }
        if self.findSubcommand(command.name()) != null {
            throw "Command.withSubcommand: duplicate name"
        }
        List<String> aliases = command.aliases()
        Int aliasIndex = 0
        while aliasIndex < aliases.length() {
            if self.findSubcommand(aliases.get(aliasIndex)) != null {
                throw "Command.withSubcommand: duplicate alias"
            }
            aliasIndex = aliasIndex + 1
        }
        List<Command> subcommands = _subcommands.copy()
        subcommands.push(command)
        return new Command(_name, _summary, _description, _aliases, _options, subcommands, _isHidden, _requireSubcommand)
    }

    Command withHidden(Bool value) {
        return new Command(_name, _summary, _description, _aliases, _options, _subcommands, value, _requireSubcommand)
    }

    Command withRequireSubcommand(Bool value) {
        return new Command(_name, _summary, _description, _aliases, _options, _subcommands, _isHidden, value)
    }

    OptionSpec? findOption(String name) {
        Int index = 0
        while index < _options.length() {
            if _options.get(index).name() == name {
                return _options.get(index)
            }
            index = index + 1
        }
        return null
    }

    OptionSpec? findOptionByShort(String shortName) {
        Int index = 0
        while index < _options.length() {
            OptionSpec option = _options.get(index)
            String? candidate = option.shortName()
            if candidate != null && candidate == shortName {
                return option
            }
            index = index + 1
        }
        return null
    }

    Command? findSubcommand(String name) {
        Int index = 0
        while index < _subcommands.length() {
            Command command = _subcommands.get(index)
            if command.name() == name { return command }
            List<String> aliases = command.aliases()
            Int aliasIndex = 0
            while aliasIndex < aliases.length() {
                if aliases.get(aliasIndex) == name { return command }
                aliasIndex = aliasIndex + 1
            }
            index = index + 1
        }
        return null
    }

    String toString() { return _name }
}
```
