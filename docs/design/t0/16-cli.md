# xdk.cli —— T0 命令行 v1.0

| 项 | 值 |
| --- | --- |
| 包 | `xdk.cli` |
| 层级 | T0 |
| 稳定性 | `preview` |
| 依赖 | `xdk.text`、`xdk.sys` |
| 被依赖 | 工具程序入口 |
| 对应源码 | `src/xdk/cli/Cli.x` |
| 当前状态 | Verified（mini；OptionSpec/Command/子命令/help/补全/短选项/默认值） |

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
| CAP-9 补全 | 从 `OptionSpec`/子命令生成 bash `complete -W` 文本 | `completionBash` |
| CAP-10 短选项与重复策略 | `-abc` 合并、首次/末次/全部值、`--` 终止符 | `OptionSpec.withShort`、`Args.expandShortFlags`、`Args.lastValue`、`Args.values` |
| CAP-11 默认值 | argv > 环境变量 > 配置值 > fallback | `resolveValue`、`defaultFromEnv` |

**非目标**：类型化值、zsh/fish 原生补全、环境变量前缀自动推导（T1）。

## 2. 契约

```text
class Args {
    Args(List<String> raw)
    Int length()
    String get(Int index)
    Int terminatorIndex()
    Bool has(String flag)
    String value(String flag)
    String lastValue(String flag)
    List<String> values(String flag)
    String valueOr(String flag, String fallback)
    List<String> positionals()
    Args expandShortFlags(List<String> knownShortFlags)
}

class OptionSpec {
    OptionSpec(String name, Bool takesValue, String help, Bool required)
    OptionSpec withShort(String shortName)
    String shortName
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
String completionBash(Command root)
String defaultFromEnv(String envName, String fallback)
String resolveValue(Args arguments, String flag, String envName, String configValue, String fallback)
```

- `has` 同时接受 `--flag` 与 `--flag=value`；flag 字符串必须包含前导 `--`。
- `value` 找不到返回空串；需要默认值时用 `valueOr`。
- 重复选项：`value` 取首次，`lastValue` 取末次，`values` 返回全部（按出现顺序）。
- `--` 是终止符：它之前的参数按 option 解释，之后全部作为位置参数；
  `has`/`value`/`values` 不越过终止符。
- `positionals` 跳过 option 及其后随值；`--flag=value` 不跳过下一项；
  `--` 之后逐项保留。
- `Args.expandShortFlags(known)` 把 `-abc` 展开为 `-a -b -c`，仅当每个短选项
  都在 `known` 中；否则原样保留。`Command.parse` 只合并“全部是 flag”的短选项簇，
  含取值选项的簇按未知选项处理。
- `OptionSpec.withShort` 返回带短名的新 spec；原 spec 不变。
- `completionBash` 生成一行根命令 `complete -W "<words>" <name>`，每个直接
  子命令再生成一行；`words` = 长选项、短名、子命令、`help`。只生成文本。
- `resolveValue` 优先级：argv 命中 > 环境变量存在 > 非空配置值 > fallback。
  `defaultFromEnv` 只做环境变量/fallback 两段。
- `usage`/`completionBash`/`help` 只生成文本，不写 stdout/stderr。
- `exitCodeFor`：ok=0、usage=2、其他=1。
- `Args` 借用 argv 列表；`expandShortFlags` 返回新 `Args`，原实例不变。
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
- 子命令匹配与 help 文本；
- `--` 终止符与位置参数；
- 重复选项的首次/末次/全部值；
- 短选项簇展开与 Command 层合并；
- `completionBash` 根命令与子命令文本；
- 默认值优先级 argv/环境/配置/fallback。

场景：`xdk_cli.x`（argv）、`r4/cli_completion.x`、`r4/cli_defaults.x`。

## 4. 后续（T1）

- 类型化值（Int/Bool/Duration）；
- zsh/fish 原生补全与环境变量前缀自动推导；
- 短选项含取值选项时的簇语法。
