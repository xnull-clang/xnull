<p align="center">
  <img src="../assets/logo.png" alt="XNull" width="640">
</p>

# XNull

**写代码，别写仪式。**

[English](../README.md) | **简体中文** | [繁體中文](README.zh-TW.md) | [Русский](README.ru.md) | [العربية](README.ar.md) | [Italiano](README.it.md) | [Deutsch](README.de.md)

*英文版为基准；其他翻译会陆续同步。*

![status: research](https://img.shields.io/badge/status-research-orange)
![compiler: mini 1.0.0](https://img.shields.io/badge/compiler-mini%201.0.0-blue)
![license: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-green)

XNull 是一门静态类型、通用目的的编程语言，自带**输出 C 的自举编译器**。编译器按规范中的判定表为每个对象选择栈、ARC 或 GC；源码永远不写生命周期或引用强度。

- **自举编译器。** `src/mini` 用 XNull 编写，并编译自身到不动点（`src/mini/tests/selfhost.sh`）。
- **C 后端，原生二进制。** 一个入口文件先变成 C，再编译成本地可执行文件；没有虚拟机。
- **错误即值。** `Result<T, E>`、`try`、`defer`/`errdefer`；没有异常，也没有隐式展开。
- **协议，而非继承。** 没有 `extends`，没有 `@Override`；字段就是字段。
- **编译期注解，无运行时反射。** 用生成代码和静态元数据代替运行时扫描。
- **规范优先。** 11 部分规范记录 XNull 支持什么、拒绝什么、为什么。

> **状态：研究与实现阶段。** 编译器可用于示例和 XDK T0 测试集；语言与标准库尚未达到生产可用。目前只有一位维护者。当前边界见 [状态](#状态)。

## 快速开始

```sh
git clone https://github.com/xnull-clang/xnull.git
cd xnull

./src/cli/xnull run src/examples/hello.x
```

```text
hello, XNull
1 + 2 = 3
```

构建原生二进制：

```sh
./src/cli/xnull build src/examples/hello.x -o /tmp/hello
/tmp/hello
```

只检查、不构建：

```sh
./src/cli/xnull check src/examples/hello.x --json
# {"ok":true}
```

需要 C11 编译器（`cc`）和 POSIX shell；少量测试脚本需要 Python 3。

## 一个例子看语言

```x
static Result<Int, String> double(Int n) {
    if n < 0 {
        return Err("negative: " + str(n))
    }
    return Ok(n * 2)
}

static Int main() {
    Int v = try double(21)
    print(v)                  // 42
    return 0
}
```

`try` 把 `Err` 作为值向上传播；没有异常展开。更多可运行示例见 [`src/examples/`](../src/examples)：类、容器、`Result`/`try`、`defer`、多文件程序。

## 当前可用

| 领域 | 状态 |
| --- | --- |
| 编译器 | `mini 1.0.0`；自举不动点；输出 C |
| CLI | `build`、`run`、`check`、`version`、`clean`、`doctor` |
| 核心语言 | 类、结构体、枚举、协议、泛型、`Result`/`try`、`defer`、任务/通道（`Mutex`、close/cancel） |
| XDK | T0 包：errors、text、math、time、collections、io/fs/sys、tasks/sync、log、config、cli；更多进行中 |
| 多文件工程 | `xnull.project` + `entryFile`；`build`/`run`/`check` |
| 工具 | Web IDE（`python3 ide/web/server.py`）、VS Code 扩展原型 |
| 测试 | `selfhost`、`xdk`、`m10_parity`、`resources`、`m8`、`m10_perf` |

尚未提供：包管理器、格式化器、工程构建与依赖编排、完整标准库、生产级加固。

**只有一个编译器，没有回退。** `src/mini` 是唯一编译器；没有第二引擎，也不做委托：mini 跑不了的命令就不提供，而不是悄悄转交给别的实现。

## 为什么是 XNull

**内存是判定表，不是注解。** 源码不表达引用强度。编译器按 DET-01 选择栈、ARC 或 GC，运行时执行这个选择。策略是封闭的、写下来的，因此可以被检查，而不是靠猜。见 [S4](../docs/solution-04-memory-management.md) 和 [`DET-01`](../docs/design/DET-01.md)。

**错误即值。** `Result<T, E>` 把失败放进类型系统；`try` 负责传播；`defer`/`errdefer` 让清理显式。没有异常，也没有隐藏的展开。见 [S5](../docs/solution-05-error-handling.md)。

**组合优于继承，且没有反射。** 多态用协议表达，不用脆弱的基类。字段是数据，不是 getter/setter。编译期注解生成代码和元数据，序列化与数据映射不需要运行时扫描。见 [S2](../docs/solution-02-object-programming.md) 和 [S3](../docs/solution-03-annotation.md)。

**有界抽象。** XNull 不追求最大的抽象空间，而追求“源码 + 规范就能判定”的设计。完整能力地图和取舍见 [S0](../docs/solution-00-language-capabilities.md)；与其他语言的对比见 [`docs/design/LANGUAGE-COMPARISON.md`](../docs/design/LANGUAGE-COMPARISON.md)。

### 明确不支持（设计如此）

| 特性 | 原因 |
| --- | --- |
| 方法重写 | 实际运行哪个方法必须能从静态类型回答；动态分派只通过协议存在 |
| 访问器 / 属性 | 字段是数据；行为是动词命名的方法 |
| 反射 | 违反“源码 + 规范决定程序”的公理 |
| 异常 | 错误即值；`throw` 仅用于致命错误，永不展开 |

## 性能

200M 次迭代的 LCG 循环是回归门禁，不是基准宣传。项目参考机最近一次 200M 次运行是 **0.675 秒**（2026-11-24），对比 mini 0.2.0 基线 0.733 秒。复现：

```sh
src/mini/tests/m10_perf.sh
```

工作负载与门禁见 [`src/mini/tests/m10_perf.sh`](../src/mini/tests/m10_perf.sh)；里程碑记录见 [`src/mini/MILESTONES.md`](../src/mini/MILESTONES.md)。

## 仓库结构

```text
src/
  cli/xnull          统一 CLI
  mini/              编译器（用 XNull 编写，自举）
  runtime/           C 运行时
  xdk/               XDK 源码
  ffi/               原始 FFI 桥接契约（.xfb）
  toolchain/         mini build/run/check 脚本
  examples/          可运行示例
docs/
  solution-00..10    11 部分规范
  design/            架构、注解、DET-01、包地图、计划
ide/
  web/               单页 Web IDE（仅 Python 标准库）
  vscode/            VS Code 扩展原型
xdk/                 XDK 交付包（install.sh）
```

`src/` 是开发树；`xdk/` 是交付副本。修改 `src/xdk/` 后，需要同步到 `xdk/lib/xdk/`。

## 文档

| 部分 | 主题 |
| --- | --- |
| [S0](../docs/solution-00-language-capabilities.md) | 能力与应用边界 |
| [S1](../docs/solution-01-basic-syntax.md) | 基础语法 |
| [S2](../docs/solution-02-object-programming.md) | 对象与协议 |
| [S3](../docs/solution-03-annotation.md) | 注解 |
| [S4](../docs/solution-04-memory-management.md) | 内存管理 |
| [S5](../docs/solution-05-error-handling.md) | 错误处理 |
| [S6](../docs/solution-06-tasks-and-concurrency.md) | 任务与并发 |
| [S7](../docs/solution-07-xdk.md) | XDK |
| [S8](../docs/solution-08-toolchain.md) | 工具链 |
| [S9](../docs/solution-09-ide.md) | IDE |
| [S10](../docs/solution-10-project-configuration.md) | 工程配置 |

设计文档索引：[`docs/design/README.md`](../docs/design/README.md)。架构基线：[`docs/design/ARCHITECTURE.md`](../docs/design/ARCHITECTURE.md)。

## 状态

| 领域 | 状态 |
| --- | --- |
| 编译器 | 自举、C 后端、单文件与最小工程面 |
| 语言 | 核心构造已实现；覆盖范围按场景逐步增长 |
| XDK | T0 包通过；T1/T2 包进行中 |
| 注解 | 注册表、代码生成与扩展进行中 |
| IDE | Web IDE 可用；VS Code 扩展为原型 |
| 发布 | 研究与实现阶段；暂不承诺稳定性 |

**路线图，按顺序：** 扩大语言覆盖 → 补全 XDK → 工程构建与格式化器 → 自举发布 → 生产级加固。队列见 [`src/mini/PLAN.md`](../src/mini/PLAN.md)；证据见 [`src/mini/MILESTONES.md`](../src/mini/MILESTONES.md)。

开发是规范优先的：特性随可执行场景和回归门禁一起落地，而不是按功能清单打勾。

XNull 刻意不试图做所有事。它不是手动控制内存的系统语言，不是依赖反射的框架语言，也不是宏/DSL 语言。如果某个特性不能由源码 + 规范判定，它就不属于这门语言。

## 贡献

XNull 从一个单人设计项目开始。当前最有用的贡献：

- 带最小复现的编译器/运行时缺陷；
- 带可执行场景的 XDK 包；
- 规范反例——好的论证会变成规范修订；
- 翻译与文档修正。

开 [issue](https://github.com/xnull-clang/xnull/issues) 或提 pull request。大改动请先开 issue，让设计先被讨论，再写代码。

## 许可证

代码（`src/`、`xdk/`、`src/examples/`）采用 Apache-2.0，见 [LICENSE](../LICENSE)。规范与文档（`docs/`、`README*.md`）采用 CC BY 4.0，见 [LICENSE-docs.md](../LICENSE-docs.md)。XNull 名称与 logo 不在这两个许可证范围内。

## 支持

XNull 是单人项目。如果愿意提供资金支持，见 [资助与赞助](../docs/FUNDING.md)。赞助自愿，不构成投资。
