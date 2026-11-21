# xdk.cli ——  命令行 v1.0

> **1.x legacy**：本文件是旧 core 包级设计/状态账本，不是 2.x 类型合同。2.x 以 [`core/`](README.md) 的逐包目录与 [`../PACKAGE-MAP.md`](../PACKAGE-MAP.md) 为准；执行层统一为 `xdk.execution`。

> **状态（2026-11-21）**：本文件是  v1 包级设计/实现状态账本。
> 公开类型与方法形态以 [`core/`](README.md) 为准；状态汇总见 [`STATUS.md`](STATUS.md)；
> 本文件的 `当前状态`、源码路径与 K/X 明细继续保留。

| 项 | 值 |
| --- | --- |
| 包 | `xdk.cli` |
| 层级 |  |
| 稳定性 | `preview` |
| 依赖 | `xdk.text`、`xdk.sys` |
| 被依赖 | 工具程序入口 |
| 对应源码 | `src/xdk/cli/Cli.x` |
| 当前状态 | Verified（mini；最小面） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 参数视图 | 原始 argv、长度、按索引 | `Args` |
| CAP-2 flag 查询 | `--name` / `--name=value` | `Args.has` |
| CAP-3 值读取 | value/valueOr | `Args` |
| CAP-4 位置参数 | 非 option 序列 | `Args.positionals` |
| CAP-5 用法文本 | program + summary | `usage` |
| CAP-6 退出码 | ok/usage/其他 | `exitCodeFor` |

**非目标**：子命令树、OptionSpec、自动 help、补全、短选项合并、类型化值。

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

String usage(String program, String summary)
Int exitCodeFor(String outcome)
```

- `has` 同时接受 `--flag` 与 `--flag=value`。
- `value` 找不到返回空串；需要默认值时用 `valueOr`。
- `positionals` 跳过 option 及其后随值；`--flag=value` 不跳过下一项。
- `usage` 只生成文本，不写 stdout/stderr。
- `exitCodeFor`：ok=0、usage=2、其他=1。
- `Args` 借用 argv 列表；不修改。

## 3. 测试义务

- flag 存在/缺失；
- `--name value` 与 `--name=value`；
- 位置参数；
- usage 文本；
- 退出码映射。

场景：`xdk_cli.x`（argv）。

## 4. 后续（X/）

- `OptionSpec`/`Command`/子命令；
- help 渲染、补全；
- 短选项合并、重复选项策略；
- 从环境/配置文件取默认值。
