# `SystemSnapshot`

| 项 | 值 |
| --- | --- |
| 类型 | `class SystemSnapshot` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `SystemInfo`、`Env` |

---

## 1. 定位

CLI 诊断用的不可变系统快照：组合 `xdk.sys.SystemInfo`（CPU/内存/磁盘/主机）、`xdk.sys.Env`（环境）、运行平台标识、进程身份。

不做：实时监控、进程表、cgroup/容器、GPU/温度/网络、写入系统状态、 `xdk.os` 的扩展资源。

---

## 2. 设计逻辑

- 组合而不是复制 `SystemInfo` 的全部字段：`systemInfo()` 返回不可变的 `SystemInfo`，常用字段提供委托读取。
- 环境以 `Env` 快照保存；`environment()` 返回快照；`describe` 只报告数量，不打印值。
- 平台字段来自 `Platform.os/arch/family/cwd`；snapshot 不缓存静态平台对象。
- 进程字段来自 `Platform.pid()`（当前进程）或 `Process.id/isAlive/exitCode`（指定子进程）。
- `processExitCodeOrNull` 只在已知退出码时非 null；进程仍存活时必须为 null。
- 所有字段构造时复制/冻结；无 close。
- 时间戳用 `capturedAtEpochMillis`（Unix epoch 毫秒，Long）；不承诺强一致时钟。
- 缺失/不可用字段沿用 `SystemInfo` 的 0/空值语义；不伪造 `Unsupported`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_systemInfo` | `SystemInfo` | 主机/CPU/内存/磁盘快照 |
| `_environment` | `Env` | 环境快照 |
| `_platformOs` | `String` | OS 标识 |
| `_platformArch` | `String` | 架构 |
| `_platformFamily` | `String` | 平台族 |
| `_workingDirectory` | `String` | 捕获时 cwd |
| `_processId` | `Long` | 进程 ID |
| `_isProcessAlive` | `Bool` | 进程是否存活 |
| `_processExitCode` | `Int?` | 已知退出码/无 |
| `_capturedAtEpochMillis` | `Long` | 捕获时间 |

不变量：

- `systemInfo`/`environment` 非 null；
- 平台/目录字符串非 null；
- `processId ≥ 0`；`capturedAtEpochMillis ≥ 0`；
- `_processExitCode != null` 时 `_isProcessAlive == false`；
- 不可变；`disks()`/`environmentKeys()` 返回副本。

---

## 4. 生命周期

构造后不可变；无 close；可跨任务共享；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SystemSnapshot(SystemInfo, Env, String, String, String, String, Long, Bool, Int?, Long)` | 见 §6 | 非 null；数值非负；存活时退出码 null | 非法 → panic |

构造器主要供 `SystemResource` 使用；测试可直接构造合法快照。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `systemInfo` | 原始系统信息 | 无 | `SystemInfo` | 无 |
| `environment` | 环境快照 | 无 | `Env` | 无 |
| `hostname` | 主机名 | 无 | `String` | 无 |
| `uptimeMillis` | uptime | 无 | `Long` | 无 |
| `cpuCores` | CPU 核数 | 无 | `Int` | 无 |
| `cpuModel` | CPU 型号 | 无 | `String` | 无 |
| `cpuFrequencyMhz` | CPU 频率 | 无 | `Int` | 无 |
| `cpuUsagePercent` | CPU 使用率 | 无 | `Double` | 无 |
| `memoryTotalBytes` | 总内存 | 无 | `Long` | 无 |
| `memoryFreeBytes` | 空闲内存 | 无 | `Long` | 无 |
| `memoryAvailableBytes` | 可用内存 | 无 | `Long` | 无 |
| `disks` | mount → 可用字节 | 无 | `Map<String,Long>` | 无 |
| `platformOs` | OS | 无 | `String` | 无 |
| `platformArch` | 架构 | 无 | `String` | 无 |
| `platformFamily` | 平台族 | 无 | `String` | 无 |
| `workingDirectory` | 捕获时 cwd | 无 | `String` | 无 |
| `processId` | 进程 ID | 无 | `Long` | 无 |
| `isProcessAlive` | 是否存活 | 无 | `Bool` | 无 |
| `processExitCodeOrNull` | 已知退出码 | 无 | `Int?` | 无 |
| `capturedAtEpochMillis` | 捕获时间 | 无 | `Long` | 无 |
| `environmentKeys` | 环境变量名快照 | 无 | `List<String>` | 无 |
| `environmentCount` | 环境变量数 | 无 | `Int` | 无 |
| `describe` | 诊断摘要（不含环境值） | 无 | `String` | 无 |
| `copy` | 复制快照 | 无 | `SystemSnapshot` | 无 |

说明：

- `systemInfo()` 返回不可变对象；其 `disks()` 仍返回副本。
- `environment()` 返回不可变 `Env`；调用方可显式读取值，但日志/诊断应只使用 `describe`。
- `environmentKeys()` 顺序沿用 `Env.keys()`；不排序。
- `copy()` 共享 `SystemInfo`/`Env`（两者不可变），复制标量字段。
- `describe` 只报告 hostname、platform、CPU、内存、磁盘数量、进程 ID/存活、环境变量数量和捕获时间。

---

## 8. 使用的技术

- 不可变组合快照；
- 委托读取；
- 映射/键列表复制；
- 平台/进程字段归一；
- epoch 毫秒时间戳。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、Long、Double、List、Map；
- 运行时：无（时间戳由 `SystemResource` 传入）；
- 接口：`SystemInfo`、`Env`。

---

## 10. 依赖的特性/接口/类

`SystemInfo`、`Env`。不直接依赖 `Platform`/`Process`；这些由 `SystemResource` 读取后传入。

---

## 11. 所有权与并发

不可变；`disks`/`environmentKeys` 返回副本；`SystemInfo`/`Env` 共享且不可变；可共享；无锁、无 close。值语义但未提供 `equals`/哈希；比较由调用方按字段完成。

---

## 12. 示例与反例

正确：

```xnull
SystemSnapshot snapshot = new SystemResource().capture()
Int cores = snapshot.cpuCores()
Long available = snapshot.memoryAvailableBytes()
Int environmentCount = snapshot.environmentCount()
```

反例：

- 把快照当实时监控，期望字段自动更新；
- 在日志中打印 `snapshot.environment().all()`；
- 期望 `processExitCodeOrNull` 在进程仍存活时非 null；
- 期望 `disks()` 返回内部 Map 并修改它；
- 用快照做强一致容量规划。

---

## 13. 测试/场景义务

字段非负；CPU 使用率范围；空磁盘/空环境；进程存活/退出；退出码与存活互斥；`environmentKeys`/`disks` 副本独立；`copy` 独立性；`describe` 不含环境值；构造非法字段 panic；捕获时间非负。

---

## 14. XNull 伪代码

```xnull
class SystemSnapshot {
    final SystemInfo _systemInfo
    final Env _environment
    final String _platformOs
    final String _platformArch
    final String _platformFamily
    final String _workingDirectory
    final Long _processId
    final Bool _isProcessAlive
    final Int? _processExitCode
    final Long _capturedAtEpochMillis

    SystemSnapshot(SystemInfo systemInfo, Env environment, String platformOs, String platformArch,
                   String platformFamily, String workingDirectory, Long processId,
                   Bool isProcessAlive, Int? processExitCode, Long capturedAtEpochMillis) {
        if systemInfo == null || environment == null {
            throw "SystemSnapshot: null source"
        }
        if platformOs == null || platformArch == null || platformFamily == null {
            throw "SystemSnapshot: null platform"
        }
        if workingDirectory == null || processId < 0 || capturedAtEpochMillis < 0 {
            throw "SystemSnapshot: invalid scalar"
        }
        if isProcessAlive && processExitCode != null {
            throw "SystemSnapshot: alive process has exit code"
        }
        _systemInfo = systemInfo
        _environment = environment
        _platformOs = platformOs
        _platformArch = platformArch
        _platformFamily = platformFamily
        _workingDirectory = workingDirectory
        _processId = processId
        _isProcessAlive = isProcessAlive
        _processExitCode = processExitCode
        _capturedAtEpochMillis = capturedAtEpochMillis
    }

    SystemInfo systemInfo() { return _systemInfo }
    Env environment() { return _environment }

    String hostname() { return _systemInfo.hostname() }
    Long uptimeMillis() { return _systemInfo.uptimeMillis() }
    Int cpuCores() { return _systemInfo.cpuCores() }
    String cpuModel() { return _systemInfo.cpuModel() }
    Int cpuFrequencyMhz() { return _systemInfo.cpuFrequencyMhz() }
    Double cpuUsagePercent() { return _systemInfo.cpuUsagePercent() }
    Long memoryTotalBytes() { return _systemInfo.memoryTotal() }
    Long memoryFreeBytes() { return _systemInfo.memoryFree() }
    Long memoryAvailableBytes() { return _systemInfo.memoryAvailable() }
    Map<String, Long> disks() { return _systemInfo.disks() }

    String platformOs() { return _platformOs }
    String platformArch() { return _platformArch }
    String platformFamily() { return _platformFamily }
    String workingDirectory() { return _workingDirectory }
    Long processId() { return _processId }
    Bool isProcessAlive() { return _isProcessAlive }
    Int? processExitCodeOrNull() { return _processExitCode }
    Long capturedAtEpochMillis() { return _capturedAtEpochMillis }

    List<String> environmentKeys() { return _environment.keys().copy() }
    Int environmentCount() { return _environment.length() }

    String describe() {
        return _systemInfo.hostname() + " " + _platformOs + "/" + _platformArch
            + " cores=" + str(_systemInfo.cpuCores())
            + " mem=" + str(_systemInfo.memoryAvailable()) + "/" + str(_systemInfo.memoryTotal())
            + " disks=" + str(_systemInfo.disks().length())
            + " process=" + str(_processId) + " alive=" + str(_isProcessAlive)
            + " env=" + str(_environment.length())
            + " captured=" + str(_capturedAtEpochMillis)
    }

    SystemSnapshot copy() {
        return new SystemSnapshot(_systemInfo, _environment, _platformOs, _platformArch,
            _platformFamily, _workingDirectory, _processId, _isProcessAlive,
            _processExitCode, _capturedAtEpochMillis)
    }
}
```
