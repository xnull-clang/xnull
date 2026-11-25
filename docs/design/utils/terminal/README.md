# `xdk.terminal` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.terminal` |
| 层 | L7 应用服务（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.io`、`xdk.text`、`xdk.collections`、核心执行层 `Context` |
| 被依赖 | 应用、CLI、构建/测试输出、运维脚本 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 0.5 实现状态（M21.4）

已实现核心 5 类型：`Color`、`Ansi`、`Style`、`Terminal`、`Table`（5/8；
ProgressBar/Spinner/Prompt 留 M21.5）。

- `Color`：basic 0..15 / indexed 0..255 / RGB、16 命名色，错误模式访问 panic；
- `Ansi`：SGR/CSI 静态包装，序列固定 `\x1b[...m`；
- `Style`：`fg/bg/boldOn/italicOn/underlineOn/render/isPlain/copy/equals`；
- `Terminal`：注入 `Writer`、终端/非终端门控、非终端剥离 CSI、clear/flush/close；
- `Table`：`+---+` 边框、可见宽度估算（忽略 CSI，Unicode 按码元近似）、
  `maxWidth` 截断、行长度/换行校验；
- 不探测 TTY/尺寸，由调用方传入；不做完整 Unicode 宽度表。

## 1. 包定位

`xdk.terminal` 提供一组**显式注入输出、可关闭 ANSI、无后台线程**的终端文本能力：

- `Terminal`：包装 `Writer` 的文本门面，带 `isTerminal`、宽高和清屏；
- `Ansi`：无状态 ANSI 转义构造器；
- `Color`：基础 8/16 色、256 索引色、RGB 的值对象；
- `Style`：前景/背景/粗体/斜体/下划线的不可变组合；
- `ProgressBar`：调用方驱动的进度条；
- `Spinner`：显式 `tick()` 的旋转指示器；
- `Prompt`：基于 `Reader`/`Writer` 的阻塞式文本、密码、确认、选择；
- `Table`：按显示宽度对齐、可处理 ANSI 单元格的表格。

本包不做“终端框架”，只做可被应用组合的基础件。所有输出都必须由调用方提供 `Writer` 或 `Terminal`；包内没有 stdout 单例、没有隐式全局配置、没有日志/国际化依赖。

不做：全屏 TUI、输入事件循环、raw mode、PTY、屏幕缓冲、光标全量寻址、Windows Console API 封装、终端能力探测、自动 ANSI 开关、后台刷新线程、密码回显控制、完整 Unicode 宽度表、树/列表/布局 DSL。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 输出显式注入 | 只接受 `Writer`/`Terminal`；不提供全局 stdout |
| 非终端纯文本 | `isTerminal=false` 时 `Terminal` 剥离 CSI/SGR；`ProgressBar`/`Spinner` 不输出动画；`Table` 单元格由调用方保证纯文本 |
| 无隐藏线程 | `ProgressBar`/`Spinner` 不创建任务或定时器；由调用方 `set`/`tick`/`finish` |
| 阻塞接受 Context | `Prompt` 的读取和写入显式接收 `Context`；取消返回 `Cancelled` |
| 值对象 | `Color`/`Style` 不可变；构建新实例而不是原地修改共享状态 |
| ANSI 与数据分离 | `Color` 只保存颜色数据；`Ansi` 才生成转义序列 |
| 宽度按显示单元 | `Table` 统计可见宽度时跳过 CSI/SGR，宽字符按 2 列估算 |
| 不复制 core | `Reader`/`Writer`/`LineReader`/`Context` 复用 `xdk.core` |
| 不依赖 log/i18n | 诊断文本由调用方提供；本包不写日志、不查消息目录 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Terminal` | class | `Writer` 文本门面/尺寸/清屏/刷新 | [`Terminal.md`](Terminal.md) |
| `Ansi` | class | 静态 ANSI/SGR/光标序列 | [`Ansi.md`](Ansi.md) |
| `Color` | class | 基础色/256 色/RGB 值对象 | [`Color.md`](Color.md) |
| `Style` | class | 不可变文本样式组合 | [`Style.md`](Style.md) |
| `ProgressBar` | class | 调用方驱动的进度渲染 | [`ProgressBar.md`](ProgressBar.md) |
| `Spinner` | class | 显式 tick 的旋转指示器 | [`Spinner.md`](Spinner.md) |
| `Prompt` | class | 文本/密码/确认/选择提示 | [`Prompt.md`](Prompt.md) |
| `Table` | class | 宽度感知的文本表格 | [`Table.md`](Table.md) |

K：上表 8 个类型。X：自动 `Spinner`（显式调度器集成）、完整 Unicode 宽度表、PTY/raw mode、密码无回显读取、Windows Console 适配、树/布局组件。

---

## 4. 顶层函数

无。`Ansi`、`Color`、`Style` 使用静态工厂；`Terminal`、`ProgressBar`、`Spinner`、`Prompt`、`Table` 使用构造器。

---

## 5. 技术/支撑/依赖

- 技术：`Writer` 适配、UTF-8 文本编码、ANSI CSI/SGR、不可变值对象、按显示宽度排布、阻塞行读取、`Context` 取消。
- 支撑：`fromUtf8`、`Writer.writeAll`/`flush`、`LineReader.readLine`、`parseInt`、`BasicError`/`ErrorKind`。
- 依赖：`xdk.errors`、`xdk.io`（`Reader`/`Writer`/`LineReader`/`Stdio`）、`xdk.text`（`parseInt`）、`xdk.collections`（`List`）、核心执行层 `Context`。

不依赖 `xdk.log`、`xdk.i18n`、`xdk.net`、`xdk.sys`。

---

## 6. 场景

### C1：交互式 CLI 进度

```xnull
Terminal terminal = new Terminal(context, Stdio.stdout(), true, 120, 40)
ProgressBar bar = new ProgressBar(terminal, 100)
Result<Unit, Error> started = bar.set(0)
if started.isErr() {
    diagnose("progress: " + started.error().describe())
} else {
    while !done {
        Result<Unit, Error> step = bar.increment()
        if step.isErr() { break }
    }
    bar.finish()
}
```

验收：每次 `set`/`increment` 只重绘一行；无后台线程；`finish` 换行。

### C2：CI/重定向输出

`Terminal(context, Stdio.stdout(), false, 0, 0)`；`ProgressBar.finish` 只输出一行纯文本；`Terminal.clear` 不写 ANSI；`Spinner.tick` 不输出转义。

### C3：带样式表格

`Style header = new Style().bold()`；单元格内容可含 `Ansi.fg`；`Table.render` 按可见宽度补齐，截断时保留转义并追加 reset。

### C4：交互提示

`Prompt prompt = new Prompt(Stdio.stdin(), Stdio.stdout())`；`prompt.text(ctx, "Name")`、`prompt.confirm(ctx, "Continue")`、`prompt.select(ctx, "Target", options)` 全部传 `Context`。`prompt.password` 只写提示语，不写用户输入。

### C5：显式旋转指示器

`Spinner spinner = new Spinner(terminal, ["|", "/", "-", "\\"], 100)`；`spinner.start(ctx)` 后由调用方循环 `spinner.tick()`；`stop` 清除当前行。自动定时属于 X，不在本包创建线程。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 全局 stdout/终端单例 | 禁止；由调用方构造 `Terminal` |
| 自动判断是否为终端 | 不做；`isTerminal` 由调用方传入，便于测试与重定向 |
| ANSI 开关 | 不做自动探测；`Terminal` 在 `isTerminal=false` 时剥离 CSI/SGR |
| OSC/超链接 | 不解析；非终端模式只保证 CSI/SGR 剥离，X 扩展 |
| 后台进度/旋转线程 | 禁止；`ProgressBar` 写入由 set/finish 触发，`Spinner` 只提供 `tick()` |
| 自动 Spinner 定时 | X；将来只通过显式调度器组合，不藏全局线程 |
| 密码回显 | `Prompt` 从不把密码写回 `Writer`；终端驱动是否回显由 Reader/PTY 决定，X 提供无回显读取 |
| Unicode 宽度 | 采用常见 wcwidth 子集估算；完整表/emoji 组合为 X |
| ANSI 截断 | `Table` 跳过 CSI，截断后追加 reset；OSC 等非 CSI 序列不在 K 范围 |
| Windows Console | 要求调用方提供 VT 兼容 Writer；原生 Console API 为 X |
| 国际化 | 主提示语由调用方传入；内置重试/确认片段为英文，不依赖 `xdk.i18n`，X 注入消息表 |
| 日志 | 不依赖 `xdk.log`；错误通过 `Result` 返回 |
| 全屏 TUI/树/布局 | X，不在本包 |

---

## 8. 依赖与顺序

```text
core/errors + core/io (Reader/Writer/LineReader/Stdio) + core/text (parseInt)
  └─ xdk.terminal
       ├─ Color
       ├─ Ansi -> Color
       ├─ Style -> Ansi + Color
       ├─ Terminal -> Writer + Ansi + Context
       ├─ ProgressBar -> Terminal
       ├─ Spinner -> Terminal + Context
       ├─ Prompt -> Reader + Writer + LineReader + Context
       └─ Table -> Ansi
```

集成顺序：先 `Color`/`Ansi`，再 `Style`/`Terminal`，最后 `ProgressBar`/`Spinner`/`Prompt`/`Table`。包内类型不反向依赖应用层。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value` |
| 处理器 | 标准 A8 |
| 生成物 | 颜色/样式值语义；提示/表格是服务 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Color`/`Style` | `@Value` | 值语义成员 |
| `ProgressBar`/`Table`/`Prompt` | — | 服务/呈现，保持显式 class |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
