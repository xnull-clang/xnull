# `xdk.schedule` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.schedule` |
| 层 | L7 应用服务（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.execution`、`xdk.runtime`、`xdk.time` |
| 被依赖 | 应用、后台任务、运维作业 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

命名作业调度：cron、一次性、固定频率、固定延迟、作业句柄、并发上限、misfire 策略、关闭。

不重复 `xdk.time.Timer`：Timer 是轻量回调定时器；本包增加命名 Job、cron、misfire、并发上限、句柄查询和结构化关闭。

不做：分布式调度、持久化、集群选主、节假日日历、UI、脚本语言。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 非泛型 Job | `Job.run(Context)` 返回 `Result<Unit, Error>`；不用泛型协议 |
| 显式时间 | `Schedule` 明确 once/fixedRate/fixedDelay/cron |
| 单调运行 | 调度循环用单调时钟；cron 用 TimeZone 计算 |
| 不重叠 | 同一 Job 默认串行，不并发重入 |
| misfire 显式 | Skip/FireOnce/CatchUp 由 options 决定 |
| 可关闭 | `shutdown(Context)` 取消/等待；Context 可取消 |
| 无全局 | 无全局调度器/作业注册表 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `ScheduleKind` | enum | Once/FixedRate/FixedDelay/Cron | [`ScheduleKind.md`](ScheduleKind.md) |
| `MisfirePolicy` | enum | Skip/FireOnce/CatchUp | [`MisfirePolicy.md`](MisfirePolicy.md) |
| `CronExpression` | class | cron 解析/下次时间 | [`CronExpression.md`](CronExpression.md) |
| `Schedule` | class | 调度规格 | [`Schedule.md`](Schedule.md) |
| `Job` | protocol | 作业协议 | [`Job.md`](Job.md) |
| `JobHandle` | class | 作业句柄/状态 | [`JobHandle.md`](JobHandle.md) |
| `SchedulerOptions` | class | 并发/misfire/时区/关闭 | [`SchedulerOptions.md`](SchedulerOptions.md) |
| `Scheduler` | class | 创建/调度/取消/关闭 | [`Scheduler.md`](Scheduler.md) |

X：分布式调度、持久化、集群选主、日历排除、Cron 名称字段、秒级以下精度。

---

## 4. 顶层函数

无。

---

## 5. 技术/支撑/依赖

- 技术：cron 解析、单调截止、工作队列、misfire、取消、句柄表。
- 支撑：`SchedulerRaw`/`JobHandleRaw`/`CronScheduleRaw`、`RuntimeMonitor`、`nowMono`、`TimeZone`。
- 依赖：`errors`、`execution`、`runtime`、`time`。

---

## 6. 场景

### J1：每日 cron

`Schedule.cron("0 3 * * *")`；`Scheduler.schedule(job, schedule)`。

### J2：固定频率

`Schedule.fixedRate(60000)`；同一 Job 串行执行。

### J3：misfire

停机后恢复；`Skip` 跳过错过，`FireOnce` 补一次，`CatchUp` 最多补 `catchUpLimit` 次。

### J4：关闭

`shutdown(ctx)`；停止接收、取消待执行、等待运行中作业。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 简单 Timer | 使用 `xdk.time.Timer` |
| 分布式/持久化 | 不做 |
| Cron 名称/时区 DST |  数字字段 + 固定偏移；DST X |
| 同一 Job 并发 | 默认禁止 |
| misfire | 三策略；CatchUp 有上限 |
| 动态修改 | 取消后重新 schedule；原地修改 X |
| 关闭超时 | 0 = 无限等待；>0 = Timeout |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@Scheduled` |
| 本包消费 | `@Value`、`@Builder` |
| 处理器 | ScheduleAnnotationProcessor（Validate/Generate） |
| 生成物 | 作业注册、cron 元数据 |
| 状态 | 领域注解 planned；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 作业方法 | `@Scheduled` | 作业注册 |
| `CronExpression`/`Schedule`/`SchedulerOptions` | `@Value`/`@Builder` | 值语义/选项 |

### 声明

```x
@Target(Method)
@Retention(Runtime)
@annotation Scheduled {
    final String cron = ""
    final Long fixedRateMillis = 0
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
class Jobs {
    @Scheduled("0 */5 * * * *")
    void refreshCache() {
        // ...
    }
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
