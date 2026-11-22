# `xdk.core` 层设计总纲

| 项 | 值 |
| --- | --- |
| 文档性质 | 层设计标准与目录规范；只写设计，不写代码 |
| 范围 | `xdk.core` 层，一个包一个系列 |
| 目标 | 每个包、每个类都有：设计逻辑、完整 API、方法用途、参数、返回、失败、生命周期、并发/取消、场景 |
| 规则 | 不讨论编译器/FFI；不写实现；不接受“只有方法名没有契约” |

>  目录的权威顺序与旧文件去重说明见 [`../README.md`](OVERVIEW.md)。

---

## 1. 为什么重做

上一版的问题是“扁平 API 清单”：

- 包与包之间没有明确的层内顺序；
- 类的方法面不完整，很多方法只有名字，没有参数/返回/失败；
- 类与类的关系没有设计逻辑，像“把函数塞进类”；
- 没有按“一个包一个系列”的方式组织，无法逐包评审。

本系列改为：

```text
xdk.core
  ├─ errors/
  │   ├─ README.md
  │   ├─ ErrorKind.md
  │   ├─ Error.md
  │   ├─ DetailedError.md
  │   ├─ ErrorDetail.md
  │   ├─ BasicError.md
  │   ├─ ErrorReport.md
  │   ├─ ErrorGroup.md
  │   ├─ RetryPolicy.md
  │   ├─ RetryState.md
  │   ├─ ErrorMatcher.md
  │   ├─ ErrorCollector.md
  │   ├─ ErrorSink.md
  │   ├─ DiagnosticErrorSink.md
  │   ├─ MemoryErrorSink.md
  │   ├─ ErrorCode.md
  │   └─ ErrorCodeRegistry.md
  ├─ runtime/
  │   ├─ README.md
  │   ├─ RuntimeInfo.md
  │   ├─ MemoryStats.md
  │   ├─ TaskStats.md
  │   ├─ TaskSnapshot.md
  │   ├─ HealthState.md
  │   ├─ HealthReport.md
  │   ├─ HealthCheck.md
  │   └─ HealthRegistry.md
  ├─ meta/
  │   ├─ README.md
  │   ├─ Capability.md
  │   ├─ CapabilitySet.md
  │   ├─ RuntimeRole.md
  │   ├─ IoModel.md
  │   ├─ ShutdownPolicy.md
  │   ├─ ResourceLimits.md
  │   ├─ CoreProfile.md
  │   ├─ ProfileBuilder.md
  │   ├─ DependencyInfo.md
  │   ├─ BuildInfo.md
  │   └─ TargetInfo.md
  ├─ bytes/
  │   ├─ README.md
  │   ├─ Bytes.md
  │   ├─ BytesBuilder.md
  │   └─ ...
  └─ ...
```

本版另加一份跨包文档 [`CORE-PROFILES.md`](CORE-PROFILES.md)：把“核心能力”分成
公共内核与 `Client`/`Server`/`Tool`/`Library` 四种画像，补齐资源上限、关闭策略、
健康面与执行层原语。它不新增语言语法，也不复制 `xdk.net` 的网络类型。

平台/硬件边界另见 [`PLATFORM-BOUNDARY.md`](PLATFORM-BOUNDARY.md)：CPU/内存/主板/GPU/防火墙/容器/虚拟化
不进 core；可选硬件/OS 服务归  `xdk.os.*`（设计见 [`../platform/os/README.md`](../platform/os/README.md)），OS 适配器归 runtime/FFI。

每个包按同一模板交付，评审时可以逐包冻结。

---

## 2. 包顺序（固定）

按依赖从底到上：

| # | 包 | 依赖 | 说明 |
| --- | --- | --- | --- |
| 01 | `errors` | 无（仅诊断） | 所有包的失败基础 |
| 02 | `runtime` | 无 | 诊断/退出/时钟 |
| 03 | `meta` | 无 | 版本/目标/能力/画像 |
| 04 | `bytes` | errors | 字节/缓冲/端序 |
| 05 | `text` | errors, bytes | 文本/格式化/Unicode |
| 06 | `collections` | errors | 容器/算法 |
| 07 | `math` | errors | 数值/Decimal/统计 |
| 08 | `time` | errors, runtime | 时长/日期/时区 |
| 09 | `io` | errors, bytes | 流/缓冲/Stdio |
| 10 | `fs` | errors, bytes, io | 路径/文件/目录 |
| 11 | `sys` | errors, runtime, bytes | 进程/环境/平台 |
| 12 | `log` | errors, runtime, text, time | 日志 |
| 13 | `config` | errors, meta, text, fs, sys | 配置 |
| 14 | `cli` | errors, text, sys, io, fs, execution | 命令行 + Shell/系统资源 |
| 15 | `execution` | errors, runtime | 执行层内建（原 `tasks`/`sync`） |

规则：

-  `annotations` 是独立层，位于 core 之前；其元模型/元注解/处理器合同见 [`../annotations/README.md`](../annotations/README.md) 与 [`../ANNOTATION-SYSTEM.md`](../ANNOTATION-SYSTEM.md)。
- core 既有 `01`–`15` 编号保持不变，以免破坏 `01`–`16` 状态账本与 `core-batches.sh`；annotations 先于 `01` 冻结。
- 后面的包可以依赖前面的包；反向依赖禁止。
- 一个包未冻结，不开始下一个包。
- 包内按“类型 → 构造 → 生命周期 → 方法 → 场景”顺序设计。

---

## 3. 包目录规范

**一个类一个文件。** 每个包目录包含：

| 文件 | 内容 |
| --- | --- |
| `README.md` | 包信息、定位、设计原则、能力与边界、类型总览/类索引、顶层函数、场景、缺口 |
| `CORE-PROFILES.md` | 客户端/服务器能力画像、资源上限、关闭策略、跨包类型补齐 |
| `PLATFORM-BOUNDARY.md` | OS/Linux、CPU/内存/主板/GPU/防火墙/平台服务归属 |
| `<ClassName>.md` | 该类的完整设计（12 项 + 技术/支撑/依赖 + XNull 伪代码） |
| `<ProtocolName>.md` | 协议的完整设计 |
| `<EnumName>.md` | 枚举的完整设计 |

规则：

- 一个公开 class 一个 PascalCase 文件；协议/枚举同理。
- 顶层函数不是类，写在包 README 的“顶层函数”段。
- 包 README 不放类的方法表/类伪代码，只放索引和包级内容。
- 不允许 `types.md`、`functions.md`、`scenarios.md`、`gaps.md`、`pseudocode.md` 这类小写辅助文件。
- 类文件必须包含：定位、设计逻辑、表示/不变量、生命周期、构造、字段、方法总表、方法详表、所有权、并发、相等、使用的技术、需要的支撑、依赖的特性/接口/类、XNull 伪代码、示例/反例、测试义务。

`// ...` 视为未完成；方法体、分支、返回值、失败通道必须写出来。运行时原语可以调用，但必须在“需要的支撑/依赖”里列出。

### 3.1 类型完整性检查（每批必做）

每批结束前必须检查：

- [ ] 包 README 的“类型总览/类索引”列出全部公开 class / enum / protocol / struct；
- [ ] 每个公开类型有独立 PascalCase 文件；
- [ ] 没有把 enum/protocol 写进 class 文件；
- [ ] 没有把多个 class 塞进一个文件；
- [ ] 每个 enum 有成员表、稳定性、技术/支撑/依赖、XNull 伪代码；
- [ ] 每个 protocol 有方法表、失败语义、实现限制、技术/支撑/依赖、XNull 伪代码；
- [ ] 类型索引链接的文件都存在，文件名与类型名一致。

示例：`text` 批曾缺 `TextAlign` 与 `NormalizationForm`，已补成独立文件，并把 `Format/Unicode` 的 Int/String 魔法值改为枚举。

---

## 4. 类设计模板（强制 12 项）

每个公开 class 必须回答：

1. **定位**：这个类让调用方能做什么，不做什么。
2. **设计逻辑**：为什么是 class 而不是 struct/enum/protocol；为什么这样拆分。
3. **表示与不变量**：字段代表什么；任何时刻必须成立什么。
4. **生命周期**：创建、使用、关闭/终结；能否重复关闭。
5. **构造契约**：每个参数的合法域；非法输入走哪个失败通道。
6. **字段表**：类型、可变性、所有权、可见性。
7. **方法总表**：完整方法清单，一眼看全。
8. **方法详表**：每个方法的用途、参数、返回、失败、复杂度、并发/取消。
9. **所有权与别名**：借用/消费/返回新所有权；是否快照。
10. **并发与重入**：线程/任务安全；能否跨任务共享；可否重入。
11. **相等/排序/哈希**：值语义还是引用语义；能否作 Map 键。
12. **示例/反例/测试义务**：最小正确用法、常见错误、场景义务。

---

## 5. 方法详表格式

每个方法一行，禁止只写“方法名 + 返回类型”：

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |

示例字段说明：

- **参数**：写名称、类型、含义、合法域。
- **返回**：成功值是什么；是否借用/新所有权/快照。
- **失败**：`Result` 错误分类，或“合同错误（panic）”，或“无失败”。
- **备注**：复杂度、并发、取消点、幂等、别名。

---

## 5.1 伪代码规范

每个非平凡方法必须带伪代码。伪代码用 **XNull 形态**写，不是语言无关的 `ALGORITHM`：

- 必须出现类的结构：`class`、字段、构造器、方法、可见性/`final`、`implements`；
- 方法体用 XNull 风格：`if`、`while`、`for item in items`、`return`、`throw`、`new`、`self`、`Result`、`Context`；
- **私有字段语法**：`_name` 字段在类内只能写裸 `_name`，不能加 `self.` 前缀；公有字段写 `self.name`（被参数遮蔽时必须写 `self.name`）；
- **返回类型**：无返回值写 `void`；`Result<Unit, E>` 的成功值写 `Ok(unit)`；不要使用大写返回类型或空参数成功构造；
- **不允许 `// ...` 或“省略实现”**；每个方法体必须写出分支、返回值、失败通道；
- 运行时原语可以调用，但必须在“需要的支撑/依赖”里逐项列出用途、返回值、失败；
- 不写编译器/FFI/内存管理细节；
- 伪代码块标 `xnull`，并写明“非可执行”；
- **伪代码必须写在该类/函数自己的文档里，不另开 `pseudocode.md`**。

示例：

```xnull
class BasicError implements Error, DetailedError {
    ErrorKind _kind
    String _message
    String _code = ""
    List<ErrorDetail> _details = []
    List<BasicError> _causes = []

    BasicError(ErrorKind kind, String message) {
        _kind = kind
        _message = message
        // 空消息按 kind 显示名归一
    }

    BasicError withCode(String code) {
        if !isValidErrorCode(code) {
            throw "BasicError.withCode: invalid code"
        }
        BasicError result = new BasicError(_kind, _message)
        result._code = code
        result._details = self.details()
        result._causes = self.causes()
        return result
    }
}
```

---

## 6. 失败通道

每个方法必须且只能属于：

- `Result<T, Error>`：可恢复失败；
- `Result<Unit, Error>`：无成功值的可恢复失败；
- 合同错误（panic）：调用方违反前置条件；
- 无失败：纯读取/纯计算。

禁止：

- 返回 `void` 却声明“非法参数 → InvalidArgument”；
- 用 `null`/`0`/空串同时表示“缺失”和“合法值”；
- 同一方法既“原样返回”又“返回 InvalidArgument”。

---

## 7. 所有权/并发/取消

- `class`：引用语义；持资源必须 `close()`；`close()` 幂等。
- `struct`：值语义；字段复制；引用字段浅复制。
- 参数默认借用；返回容器明确副本/转移/快照。
- 可阻塞方法首参 `Context`；取消 `Cancelled`，超时 `Timeout`。
- 并发承诺必须写：可共享/不可共享、可重入/不可重入。

---

## 8. 命名与稳定性

- 类型 PascalCase；方法 lowerCamelCase 动词；布尔 `is/has/can/should`。
- 参数全名：`text`、`prefix`、`separator`、`index`、`context`、`maximumBytes`。
- 每个公开符号标 `stable` / `preview` / `internal`。
- 不新增“util/common/misc/helpers”式包；一个包一个职责。

---

## 9. 包完成标准

一个包只有同时满足以下条件才可冻结：

- [ ] 包 README 的能力/非目标/依赖/K-X 完整；
- [ ] 每个公开 class 有 12 项；
- [ ] 每个方法有用途/参数/返回/失败/复杂度/并发；
- [ ] 每个资源有生命周期/close/关闭后行为；
- [ ] 每个可阻塞点有 Context/取消语义；
- [ ] 包级场景覆盖成功/失败/边界/取消/资源；
- [ ] 没有“或/待定/见下/双版本”；
- [ ] 与前后包的依赖无环、无同名换义。

---

## 10. 当前进度

| 包 | 状态 | 文档 |
| --- | --- | --- |
| `errors` | 已交付（待评审） | `errors/` |
| `runtime` | 已交付（待评审；含健康面） | `runtime/` |
| `meta` | 已交付（待评审；含角色/能力画像） | `meta/` |
| `bytes` | 已交付（待评审） | `bytes/` |
| `text` | 已交付（待评审） | `text/` |
| `collections` | 已交付（待评审） | `collections/` |
| `math` | 已交付（待评审） | `math/` |
| `time` | 已交付（待评审） | `time/` |
| `io` | 已交付（待评审） | `io/` |
| `fs` | 已交付（待评审） | `fs/` |
| `sys` | 已交付（待评审） | `sys/` |
| `log` | 已交付（待评审；X sink/过滤后续） | `log/` |
| `config` | 已交付（待评审；含画像来源） | `config/` |
| `cli` | 设计完成（含 Shell/系统资源；X completion/positional 后续） | `cli/` |
| 执行层 `xdk.execution`（1.x `tasks`/`sync` 兼容） | 已交付（待评审；含 Executor/RwLock/Semaphore/WaitGroup/Once/Pool/Future/Promise） | `execution/` |

> `xdk.annotations` 是独立注解层（14 类型 + 编译器注解管线 + Registry 已实现；A8/领域处理器 planned），不计入 2.x core 的 15 包实现状态；见 [`../annotations/README.md`](../annotations/README.md)。

> L3 已覆盖 `io`、`fs`、`sys`、`log`、`config`、`cli`；L4 执行层已覆盖 `Context`/`TaskHandle`/`Task`/`TaskGroup`/`Mutex`/`Channel`/`Atomic*`，并补齐 `Executor`/`Semaphore`/`RwLock`/`WaitGroup`/`Once`/`Pool`/`Future`/`Promise`；`CORE-PROFILES.md` 定义客户端/服务器画像与资源上限。
>
> 新增的 `preview` 类型是**设计交付**，不代表 `src/xdk` 已实现；实现批次必须同时补场景和门禁。
>
> 下一批进入 L5 `net`：复用 `docs/design/network/net`，不重复定义网络类型；核心层只保留画像、上限、健康与执行原语。
>
> `cli` 完整性检查：README 索引 17 个类型 = 17 个文件；`ExitCode` 枚举独立；`ValueParser` 协议独立；新增 `Shell`/`CommandLine`/`CommandResult`/`CommandOutput`/`ShellOptions`/`SystemResource`/`SystemSnapshot`/`CliRuntime`；无 class 内嵌 enum/protocol。
>
> 执行层完整性检查：README 索引 17 个类型 = 17 个文件；`TaskHandle` 协议独立；`Executor`/`Semaphore`/`RwLock`/`WaitGroup`/`Once`/`Pool`/`Future`/`Promise` 独立成文件；无 class 内嵌 enum/protocol；已通过返回类型、Unit 成功值、私有字段、括号/花括号扫描。
