# `PowerMode`

| 项 | 值 |
| --- | --- |
| 类型 | `enum PowerMode` |
| 包 | `xdk.embedded` |
| 层 |  |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

嵌入式目标**低功耗模式分类**：`Active`、`Idle`、`Sleep`、`DeepSleep`、`Off`，用于 `Embedded.setPowerMode`/`sleepFor` 与 `Board.powerModes`。

不做：具体唤醒源配置（GPIO/RTC/UART/CAN）、电源域/稳压器控制、频率调节策略、睡眠时长调度、RTOS tickless 集成。唤醒源与电源域是 X；模式语义只回答“CPU/外设/句柄大致处于什么状态”。

---

## 2. 设计逻辑

- 为什么是 enum：模式集合跨 MCU 稳定，且需要统一的“是否运行/是否低功耗/是否可能使句柄失效/是否需要唤醒源”谓词；字符串会让平台差异泄漏到调用方。
- 为什么是五个成员：覆盖从全速到受控关机的常见层次，又不把厂商专有模式（STOP0/STOP2、LPM3、Hibernate 等）塞进公共 API；厂商模式由适配器映射到最近的成员，映射不了返回 `Unsupported`。
- `Active` 是唯一必须出现在 `Board.powerModes` 中的成员；没有 `Active` 的板描述非法。
- `Idle`：CPU 时钟可停，外设/总线通常仍在；中断可唤醒；句柄通常不失效，但本包不承诺平台不会关闭个别外设。
- `Sleep`：大部分外设时钟门控，RAM 保留；需要配置唤醒源；句柄可能失效（保守标记为失效）。
- `DeepSleep`：核心/外设电源关闭，仅保留域/RAM 子集；唤醒可能走复位/恢复路径；句柄失效。
- `Off`：受控关机/断电；只有外部复位/电源按钮等能重新启动；进程不假设还能继续执行；句柄失效。
- 稳定序号：成员码 0..4 固定，只允许追加；不得重排/复用。
- 值语义；无实例字段；可作 `Map`/`Set` 键；无 `close`。

---

## 3. 表示与不变量

| 成员 | 码 | CPU | 外设/RAM | 句柄可能失效 | 需要唤醒源 | 说明 |
| --- | ---: | --- | --- | --- | --- | --- |
| `Active` | 0 | 运行 | 正常 | 否 | 否 | 全速/正常工作 |
| `Idle` | 1 | 可停时钟 | 通常保留 | 否 | 否 | 中断可唤醒；轻量省电 |
| `Sleep` | 2 | 停 | 大部分门控/RAM 保留 | 是 | 是 | 需配置唤醒源；恢复较快 |
| `DeepSleep` | 3 | 关 | 仅保留域 | 是 | 是 | 可能复位/恢复；恢复较慢 |
| `Off` | 4 | 关 | 关 | 是 | 是 | 受控关机；需外部复位/上电 |

不变量：5 项固定；码 0..4 固定；`Active` 必须被板支持；`powerModeIsRunning` 仅 `Active`/`Idle` 为 `true`；`powerModeIsLowPower` 仅 `Idle`/`Sleep`/`DeepSleep`/`Off` 为 `true`；`powerModeInvalidatesHandles` 仅 `Sleep`/`DeepSleep`/`Off` 为 `true`；`powerModeRequiresWakeSource` 仅 `Sleep`/`DeepSleep`/`Off` 为 `true`。

允许的转换（适配器可拒绝个别边）：

- `Active` → `Idle`/`Sleep`/`DeepSleep`/`Off`；
- `Idle` → `Active`/`Sleep`/`DeepSleep`/`Off`；
- `Sleep` → `Active`/`DeepSleep`/`Off`；
- `DeepSleep` → `Active`（恢复/复位后）；
- `Off` → 只能经外部复位/上电重新进入 `Active`。

转换由 `Embedded` 校验 + 适配器执行；本枚举只提供分类与谓词，不拥有状态机。

---

## 4. 生命周期

编译期/加载期固定；无实例；无 `close`；可跨线程共享；可长期持有。模式值不随运行时状态变化；当前模式由 `Embedded.powerMode(context, board)` 查询。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 无公开构造 | 无 | 仅枚举成员 | 禁止实例化 |

成员由语言/宿主固定；配置/日志中的模式名应由板级包维护显式映射；未知名称返回 `InvalidArgument`，不得静默回退到 `Active`（那会掩盖省电配置错误）。

---

## 6. 字段表

无实例字段；成员即值。`Board.powerModes` 存储成员集合，构造时复制并校验非空/含 `Active`/无重复。

---

## 7. 方法总表 / 详表

| 成员/函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `Active` | 全速运行 | 无 | 成员 | 无 |
| `Idle` | 轻量省电 | 无 | 成员 | 无 |
| `Sleep` | 睡眠 | 无 | 成员 | 无 |
| `DeepSleep` | 深度睡眠 | 无 | 成员 | 无 |
| `Off` | 受控关机 | 无 | 成员 | 无 |
| `powerModeIsRunning` | CPU 是否继续运行 | `PowerMode powerMode` | `Bool` | 无 |
| `powerModeIsLowPower` | 是否低功耗 | `PowerMode powerMode` | `Bool` | 无 |
| `powerModeInvalidatesHandles` | 是否可能使句柄失效 | `PowerMode powerMode` | `Bool` | 无 |
| `powerModeRequiresWakeSource` | 是否需要唤醒源 | `PowerMode powerMode` | `Bool` | 无 |
| `powerModeDescribe` | 稳定描述名 | `PowerMode powerMode` | `String` | 无 |

说明：

- `powerModeIsRunning`：`Active`/`Idle` 为 `true`；`Sleep`/`DeepSleep`/`Off` 及 `null` 为 `false`。
- `powerModeIsLowPower`：`Idle`/`Sleep`/`DeepSleep`/`Off` 为 `true`；`Active` 及 `null` 为 `false`。
- `powerModeInvalidatesHandles`：`Sleep`/`DeepSleep`/`Off` 为 `true`；`Active`/`Idle` 及 `null` 为 `false`。这是保守承诺：即使某平台在 `Sleep` 保留某些外设，调用方也应按“可能失效”处理。
- `powerModeRequiresWakeSource`：`Sleep`/`DeepSleep`/`Off` 为 `true`；`Active`/`Idle` 及 `null` 为 `false`。`Off` 的“唤醒源”是外部复位/上电，不是软件配置。
- `powerModeDescribe` 返回稳定成员名（如 `"DeepSleep"`），用于日志；`null` 返回 `"Unknown"` 作为诊断兜底，`"Unknown"` 不是枚举成员。
- 不提供 `fromName`/`next`/`deeper`：模式选择由板能力与应用策略决定，不做隐式降级/升级。

---

## 8. 使用的技术

- 稳定枚举码；
- 模式分类表；
- 谓词函数；
- 值语义；
- 稳定名称描述。

---

## 9. 需要的支撑

- 语言：enum、Int、Bool、String；
- 运行时：无；实际模式切换由 `Embedded` 的适配器原语执行；
- 接口：`Board.powerModes`、`Embedded.setPowerMode`、`Embedded.sleepFor`。

---

## 10. 依赖的特性/接口/类

无直接类型依赖；被 `Board`（支持模式集合）、`Embedded`（切换/查询/有界休眠）使用。与 `xdk.core` 执行层的调度/取消无关：进入低功耗不创建任务，也不改变 `Context` 语义。

---

## 11. 所有权与并发

值语义；不可变；可跨线程共享；无资源；无取消点；无 `close`。
相等：成员身份；可作 `Map`/`Set` 键；排序按稳定码（仅诊断用）。

---

## 12. 示例与反例

正确：`board.supportsPowerMode(PowerMode.DeepSleep)` 为 `true` 时才暴露深度休眠；进入前关闭 ADC/PWM/UART/CAN 句柄，唤醒后重新打开。

正确：`powerModeInvalidatesHandles(PowerMode.Sleep)` 为 `true`，调用方不假设 UART 句柄仍可用。

反例：把 `Idle` 当“所有外设都关闭”；把 `Sleep` 当“RAM 一定保留全部”；在 `Off` 之后继续使用任何句柄；把厂商 `STOP2` 直接映射成 `DeepSleep` 却不校验唤醒行为；未知模式名静默回退到 `Active`；用 `powerModeIsRunning` 判断句柄是否有效（应使用 `powerModeInvalidatesHandles` 或重新打开）。

---

## 13. 测试场景义务

5 个成员的 `powerModeIsRunning`/`powerModeIsLowPower`/`powerModeInvalidatesHandles`/`powerModeRequiresWakeSource` 真值表；`powerModeDescribe` 稳定名；值相等；可作 `Set`/`Map` 键；`Active` 必在 `Board.powerModes`；未知模式名映射失败；`Off` 后不继续执行；`Sleep`/`DeepSleep` 句柄失效路径；`Idle` 句柄保留路径；转换表覆盖；追加成员不改变旧码。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum PowerMode {
    Active,
    Idle,
    Sleep,
    DeepSleep,
    Off,
}

Bool powerModeIsRunning(PowerMode powerMode) {
    if powerMode == PowerMode.Active { return true }
    if powerMode == PowerMode.Idle { return true }
    return false
}

Bool powerModeIsLowPower(PowerMode powerMode) {
    if powerMode == PowerMode.Idle { return true }
    if powerMode == PowerMode.Sleep { return true }
    if powerMode == PowerMode.DeepSleep { return true }
    if powerMode == PowerMode.Off { return true }
    return false
}

Bool powerModeInvalidatesHandles(PowerMode powerMode) {
    if powerMode == PowerMode.Sleep { return true }
    if powerMode == PowerMode.DeepSleep { return true }
    if powerMode == PowerMode.Off { return true }
    return false
}

Bool powerModeRequiresWakeSource(PowerMode powerMode) {
    if powerMode == PowerMode.Sleep { return true }
    if powerMode == PowerMode.DeepSleep { return true }
    if powerMode == PowerMode.Off { return true }
    return false
}

String powerModeDescribe(PowerMode powerMode) {
    if powerMode == null { return "Unknown" }
    if powerMode == PowerMode.Active { return "Active" }
    if powerMode == PowerMode.Idle { return "Idle" }
    if powerMode == PowerMode.Sleep { return "Sleep" }
    if powerMode == PowerMode.DeepSleep { return "DeepSleep" }
    return "Off"
}
```
