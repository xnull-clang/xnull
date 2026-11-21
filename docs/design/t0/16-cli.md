# xdk.cli —— T0 命令行 v1.0

| 项 | 值 |
| --- | --- |
| 包 | `xdk.cli` |
| 层级 | T0 |
| 稳定性 | `preview` |
| 依赖 | `xdk.text`、`xdk.sys` |
| 被依赖 | 工具程序入口 |
| 对应源码 | `src/xdk/cli/Cli.x` |
| 当前状态 | Verified（mini；OptionSpec/Command/子命令/help） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 参数视图 | 原始 argv、长度、按索引 | `Args` |
| CAP-2 flag 查询 | `--name` / `--name=value` | `Args.has` |
| CAP-3 值读取 | value/valueOr | `Args` |
| CAP-4 位置参数 | 非 option 序列 | `Args.positionals` |
| CAP-5 用法文本 | program + summary | `usage` |
| CAP-6 退出码 | ok/usage/其他 | `exitCodeFor` |
| CAP-7 命令 | 选项规格、子命令、校验 | `OptionSpec`、`Command`、`CommandMatch` |
| CAP-8 help | usage/选项/子命令文本 | `Command.help` |

**非目标**：补全、短选项合并、重复选项策略、类型化值（T1）。

## 2. 契约

```text
class Args {
    Args(List<String> raw)
    Int length()
    String get(Int index)
    Bool has(String flag)
    String value(String flag)
    String valueOr(String flag, String fallback)
    List<String> positionals()
}

class OptionSpec {
    OptionSpec(String name, Bool takesValue, String help, Bool required)
}
class CommandMatch { CommandMatch(Args arguments, String command) }
class Command {
    Command(String name, String summary, List<OptionSpec> options)
    void add(Command child)
    List<Command> children()
    Result<CommandMatch, Error> parse(Args arguments)
    String help()
}

String usage(String program, String summary)
Int exitCodeFor(String outcome)
```

- `has` 同时接受 `--flag` 与 `--flag=value`；flag 字符串必须包含前导 `--`。
- `value` 找不到返回空串；需要默认值时用 `valueOr`。
- `positionals` 跳过 option 及其后随值；`--flag=value` 不跳过下一项。
- `usage` 只生成文本，不写 stdout/stderr。
- `exitCodeFor`：ok=0、usage=2、其他=1。
- `Args` 借用 argv 列表；不修改。
- `Command.parse` 校验必填/取值/未知选项；子命令按首个位置参数匹配。
- 未知命令/选项/缺失必填 → `InvalidArgument`；不隐式退出。
- `Command.help` 返回文本，不写 stdout/stderr；包含 usage、选项、子命令。

## 3. 测试义务

- flag 存在/缺失；
- `--name value` 与 `--name=value`；
- 位置参数；
- usage 文本；
- 退出码映射；
- Command 必填/取值/未知选项；
- 子命令匹配与 help 文本。

场景：`xdk_cli.x`（argv）。

## 4. 后续（T1）

- 补全；
- 短选项合并、重复选项策略；
- 从环境/配置文件取默认值。
