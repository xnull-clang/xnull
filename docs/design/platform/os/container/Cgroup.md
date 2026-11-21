# `Cgroup`

| 项 | 值 |
| --- | --- |
| 类型 | `class Cgroup` |
| 包 | `xdk.os.container` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

单个 cgroup 条目的只读快照：路径、控制器、内存限制、CPU 权重。

不做：写入/冻结/杀进程、创建/删除 cgroup、资源分配、统计采样、cgroup v1/v2 迁移。

---

## 2. 设计逻辑

- 不可变快照；由 `ContainerHost.cgroups(context)` 或 `ContainerInfo.cgroups()` 返回。
- `path` 是 cgroup 层级中的 OS 可见路径；不是应用可写文件路径，也不承诺是挂载点；
  `path` 可能包含容器标识，日志中应截断或省略。
- `controllers` 是适配器识别到的控制器名（如 `cpu`、`memory`、`pids`、`io`）；列表可空。
- `memoryLimitBytes` 是当前 cgroup 的内存上限，不是宿主总内存；`0` 表示未设置限制；适配器无法读取时也返回 `0`，
  调用方不能仅凭 `0` 区分“无限制”和“未知”；字节数用 `Long`。
- `cpuWeight` 是适配器归一后的 CPU 权重；`0` 表示未设置或未知；正数为 OS 报告值；不承诺 v1/v2 数值语义完全等价。
- 列表复制；调用方修改返回值不影响快照。
- 为什么是 class：四个字段组成一个稳定快照；不用 enum 因为含路径/列表/数值。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_path` | `String` | final | 非 null；OS 可见 cgroup 路径 |
| `_controllers` | `List<String>` | final | 非 null；元素非 null；副本 |
| `_memoryLimitBytes` | `Long` | final | ≥0；0 = 未设置限制/不可读 |
| `_cpuWeight` | `Int` | final | ≥0；0 = 未设置/未知 |

不变量：`path`/`controllers` 非 null；数值 ≥0；不可变；`controllers` 返回副本。

---

## 4. 生命周期

构造后不可变；无 close；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Cgroup(String path, List<String> controllers, Long memoryLimitBytes, Int cpuWeight)` | path、controllers、memoryLimitBytes、cpuWeight | path/controllers 非 null；数值 ≥0 | null 或负数 → panic |

构造器主要供适配器/测试使用；业务代码通过 `ContainerHost.cgroups` 或 `ContainerInfo.cgroups` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `path` | cgroup 路径 | 无 | `String` | 无 | O(1) |
| `controllers` | 控制器名快照 | 无 | `List<String>` | 无 | O(n) 复制 |
| `memoryLimitBytes` | 内存上限 | 无 | `Long` | 无 | O(1)；0 = 未设置限制/不可读 |
| `cpuWeight` | CPU 权重 | 无 | `Int` | 无 | O(1)；0 = 未设置/未知 |
| `describe` | 单行摘要 | 无 | `String` | 无 | O(n)；仅诊断 |

无 equals/copy：需要比较时逐字段比较；`==` 是引用身份。

---

## 8. 使用的技术

- 不可变快照；
- 列表复制；
- 字节数 `Long`；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、List、Long、Int；
- 运行时/适配器：cgroup v1/v2 读取；
- 接口：`ContainerHost`、`ContainerInfo`。

---

## 10. 依赖的特性/接口/类

`ContainerInfo`、`ContainerHost`、`Namespace`。

---

## 11. 所有权与并发

引用语义；不可变；可跨任务共享；`controllers` 返回副本；无资源；无取消点。
相等：`==` 是引用身份；本基线不提供 `equals`；需要比较时逐字段比较；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：用 `memoryLimitBytes()` 调整 worker/缓存上限；用 `controllers()` 判断可用控制器。  
反例：把 `path` 当应用可写路径；把 `0` 当“无限制”而不检查语义；假设 v1/v2 权重等价；
把当前容器 cgroup 当宿主全部；用 cgroup 路径做持久 ID。

---

## 13. 测试/场景义务

cgroup v1/v2；空控制器列表；`memoryLimitBytes=0`；`cpuWeight=0`；负数/null 构造 panic；
列表副本独立性；长路径；多 cgroup；容器/非容器；受限读取 `PermissionDenied`。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Cgroup {
    final String _path
    final List<String> _controllers
    final Long _memoryLimitBytes
    final Int _cpuWeight

    Cgroup(String path, List<String> controllers,
           Long memoryLimitBytes, Int cpuWeight) {
        if path == null || controllers == null {
            throw "Cgroup: null field"
        }
        if memoryLimitBytes < 0 || cpuWeight < 0 {
            throw "Cgroup: negative field"
        }
        _path = path
        _controllers = controllers.copy()
        _memoryLimitBytes = memoryLimitBytes
        _cpuWeight = cpuWeight
    }

    String path() { return _path }

    List<String> controllers() { return _controllers.copy() }

    Long memoryLimitBytes() { return _memoryLimitBytes }

    Int cpuWeight() { return _cpuWeight }

    String describe() {
        return "cgroup " + _path
            + " controllers=" + str(_controllers.length())
            + " memoryLimit=" + str(_memoryLimitBytes)
            + " cpuWeight=" + str(_cpuWeight)
    }
}
```
