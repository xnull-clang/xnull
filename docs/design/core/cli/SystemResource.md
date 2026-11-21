# `SystemResource`

| 项 | 值 |
| --- | --- |
| 类型 | `class SystemResource` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `SystemInfo`、`Env`、`Platform`、`Process`、`SystemSnapshot` |

---

## 1. 定位

只读系统资源探针：从 `xdk.sys` 的 `SystemInfo`、`Env`、`Platform`、`Process` 读取一次快照，组装成不可变 `SystemSnapshot`。

注意：本类型不是 `xdk.sys.Resource`（内嵌资源）；它只做主机/进程资源读取。

不做：实时监控、后台采样、进程枚举、cgroup/容器、GPU/温度/网络、写文件/改环境/发信号、 `xdk.os` 的扩展资源、缓存或单例。

---

## 2. 设计逻辑

- 无状态；每次 `capture` 都重新读取，不缓存上一次结果。
- `capture()` 使用当前进程：`Platform.pid()`、`isProcessAlive = true`、退出码 null。
- `captureProcess(Process process)` 使用给定子进程句柄的 `exitCode`/`id`/`isAlive`；先读 `exitCode`，非 null 时直接视为已退出，避免“刚退出”竞态违反快照不变量；不 wait、不 signal、不 close，调用方仍拥有进程。
- 主机/CPU/内存/磁盘来自 `SystemInfo.snapshot()`；环境来自 `Env.snapshot()`；平台字段来自 `Platform`。
- `SystemInfo` 的缺失字段保持 0/空；本类不把缺失改写成错误。
- 所有读取都是只读；不修改环境、不 chdir、不写文件、不启动进程。
- 无 `Result`：底层 `SystemInfo.snapshot`/`Env.snapshot`/`Platform` 均不返回可恢复失败；权限/平台限制表现为 0/空字段或 `Platform` 的稳定值。
- 时间戳使用 `capturedAtEpochMillis`；只用于排序/诊断，不承诺跨进程强一致。

---

## 3. 表示与不变量

无实例字段。实现必须保证：

- 不缓存 `SystemInfo`/`Env`/`Process`；
- 不修改传入的 `Process`；
- 不在 `capture` 中阻塞或等待子进程；
- `captureProcess` 的进程字段与传入句柄一致；
- 输出快照满足 `SystemSnapshot` 的不变量。

---

## 4. 生命周期

无状态；构造后复用；无 close；可共享；每次调用产生新快照。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SystemResource()` | 无 | 无 | 无 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `capture` | 当前系统/当前进程快照 | 无 | `SystemSnapshot` | 无 |
| `captureProcess` | 当前系统/指定进程快照 | `Process process` | `SystemSnapshot` | null → panic |

说明：

- `capture` 与 `captureProcess` 都读取当前主机/环境/平台；区别只在进程字段。
- `captureProcess` 不调用 `wait`/`exitCode` 的阻塞变体；`Process.exitCode` 只读缓存。
- `captureProcess` 不改变进程所有权；调用方仍负责 `close`。
- 两次 `capture` 之间系统值可变；快照不承诺与后续读取一致。

---

## 8. 使用的技术

- 只读探针；
- 快照组合；
- 平台/进程字段归一；
- epoch 毫秒时间戳；
- 无缓存。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Long、Int；
- 运行时：`nowEpochMillis`（epoch 毫秒）、`SystemInfo.snapshot`、`Env.snapshot`、`Platform` 查询、`Process.id/isAlive/exitCode`；
- 接口：`SystemInfo`、`Env`、`Platform`、`Process`、`SystemSnapshot`。

---

## 10. 依赖的特性/接口/类

`SystemInfo`、`Env`、`Platform`、`Process`、`SystemSnapshot`、`nowEpochMillis`。

---

## 11. 所有权与并发

无状态；可共享；不持有 `Process`/`Env`/`SystemInfo` 所有权；`captureProcess` 借用 `Process`，不 close；并发调用各自产生独立快照。无实例值，不适用相等/哈希。

---

## 12. 示例与反例

正确：

```xnull
SystemResource resource = new SystemResource()
SystemSnapshot snapshot = resource.capture()
```

```xnull
Process process = builder.spawn(context).value()
SystemSnapshot snapshot = resource.captureProcess(process)
```

反例：

- 期望 `capture` 自动刷新同一个快照；
- 在 `captureProcess` 中 wait/kill/close 进程；
- 期望列出所有进程；
- 期望 cgroup/容器/GPU/温度/网络字段；
- 用 `capture` 做秒级监控采样（应显式循环并接受快照语义）；
- 把快照当权限/容量决策的强一致来源。

---

## 13. 测试/场景义务

当前进程快照；指定存活进程；指定已退出进程；退出码与存活互斥；环境为空/非空；磁盘为空/非空；CPU 字段；平台字段；两次快照独立；`captureProcess(null)` panic；不修改进程（wait/kill 未被调用）；不修改环境/cwd。

---

## 14. XNull 伪代码

```xnull
class SystemResource {
    SystemResource() {
    }

    SystemSnapshot capture() {
        SystemInfo systemInfo = SystemInfo.snapshot()
        Env environment = Env.snapshot()
        Long processId = Platform.pid()
        return new SystemSnapshot(
            systemInfo,
            environment,
            Platform.os(),
            Platform.arch(),
            Platform.family(),
            Platform.cwd(),
            processId,
            true,
            null,
            nowEpochMillis())
    }

    SystemSnapshot captureProcess(Process process) {
        if process == null {
            throw "SystemResource.captureProcess: null process"
        }
        SystemInfo systemInfo = SystemInfo.snapshot()
        Env environment = Env.snapshot()
        Int? exitCode = process.exitCode()
        Bool isAlive = false
        if exitCode == null {
            isAlive = process.isAlive()
        }
        return new SystemSnapshot(
            systemInfo,
            environment,
            Platform.os(),
            Platform.arch(),
            Platform.family(),
            Platform.cwd(),
            process.id(),
            isAlive,
            exitCode,
            nowEpochMillis())
    }
}
```

> `nowEpochMillis` 是运行时时间原语；`Process.exitCode` 返回已知退出码或 null，不阻塞。
