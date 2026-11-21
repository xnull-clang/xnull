# `CpuTopology`

| 项 | 值 |
| --- | --- |
| 类型 | `class CpuTopology` |
| 包 | `xdk.os.cpu` |
| 稳定性 | `preview` |
| 依赖 | `CpuCore`、`CpuCache` |

---

## 1. 定位

CPU 拓扑只读快照：逻辑 CPU、缓存、ISA 特性、socket/NUMA 数。

不做：绑核、调度、热插拔、性能计数、超频。

---

## 2. 设计逻辑

- 快照由 `OsHost.cpuTopology(context)` 返回；不自动刷新。
- `cores` 是逻辑 CPU；`caches` 是缓存层级；`features` 是 ISA 特性名。
- `socketCount`/`numaNodeCount` 是 OS 可见值；容器内可能被裁剪。
- `physicalCoreCount` 按 `(socketId, coreId)` 去重计算。
- `logicalCoreCount` 等于 `cores.length()`。
- 不可变；列表返回副本。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_cores` | `List<CpuCore>` | final | 逻辑 CPU 快照 |
| `_caches` | `List<CpuCache>` | final | 缓存快照 |
| `_features` | `List<String>` | final | ISA 特性 |
| `_socketCount` | `Int` | final | ≥0 |
| `_numaNodeCount` | `Int` | final | ≥0 |

不变量：列表非 null；计数 ≥0；不可变；列表返回副本。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CpuTopology(...)` | 5 个字段 | 列表非 null；计数 ≥0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `cores` | 逻辑 CPU 快照 | 无 | `List<CpuCore>` | 无 |
| `caches` | 缓存快照 | 无 | `List<CpuCache>` | 无 |
| `features` | ISA 特性 | 无 | `List<String>` | 无 |
| `socketCount` | socket 数 | 无 | `Int` | 无 |
| `numaNodeCount` | NUMA 节点数 | 无 | `Int` | 无 |
| `physicalCoreCount` | 物理核数 | 无 | `Int` | 无 |
| `logicalCoreCount` | 逻辑核数 | 无 | `Int` | 无 |
| `findCore` | 按 id 查找 | `Int id` | `CpuCore?` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `copy` | 复制 | 无 | `CpuTopology` | 无 |

---

## 8. 使用的技术

- 快照；
- 列表复制；
- 物理核去重；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、List、Int、String、Bool；
- 运行时/适配器：CPU 拓扑读取；
- 接口：`CpuCore`、`CpuCache`。

---

## 10. 依赖的特性/接口/类

`CpuCore`、`CpuCache`、`CpuAffinity`、`OsHost`。

---

## 11. 所有权与并发

不可变；可共享；`cores/caches/features` 返回副本；无资源；无取消点。
相等：引用身份；需要比较时逐字段/逐列表比较；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`topology.logicalCoreCount()` 决定 worker 上限；`features()` 选择向量路径。  
反例：假设 id 连续；把容器可见拓扑当宿主全部；快照长期不刷新。

---

## 13. 测试/场景义务

单/多 socket；SMT；NUMA；缓存层级；特性列表；容器裁剪；findCore；physical/logical 计数；
copy 独立性。

---

## 14. XNull 伪代码

```xnull
class CpuTopology {
    final List<CpuCore> _cores
    final List<CpuCache> _caches
    final List<String> _features
    final Int _socketCount
    final Int _numaNodeCount

    CpuTopology(List<CpuCore> cores, List<CpuCache> caches,
                List<String> features, Int socketCount, Int numaNodeCount) {
        if cores == null || caches == null || features == null {
            throw "CpuTopology: null list"
        }
        if socketCount < 0 || numaNodeCount < 0 {
            throw "CpuTopology: negative count"
        }
        _cores = cores.copy()
        _caches = caches.copy()
        _features = features.copy()
        _socketCount = socketCount
        _numaNodeCount = numaNodeCount
    }

    List<CpuCore> cores() { return _cores.copy() }
    List<CpuCache> caches() { return _caches.copy() }
    List<String> features() { return _features.copy() }
    Int socketCount() { return _socketCount }
    Int numaNodeCount() { return _numaNodeCount }
    Int logicalCoreCount() { return _cores.length() }

    Int physicalCoreCount() {
        List<String> seen = []
        Int index = 0
        while index < _cores.length() {
            CpuCore core = _cores.get(index)
            String key = str(core.socketId()) + ":" + str(core.coreId())
            Bool exists = false
            Int scan = 0
            while scan < seen.length() {
                if seen.get(scan) == key { exists = true; break }
                scan = scan + 1
            }
            if !exists { seen.push(key) }
            index = index + 1
        }
        return seen.length()
    }

    CpuCore? findCore(Int id) {
        Int index = 0
        while index < _cores.length() {
            if _cores.get(index).id() == id {
                return _cores.get(index)
            }
            index = index + 1
        }
        return null
    }

    String describe() {
        return "cpu sockets=" + str(_socketCount)
            + " physical=" + str(self.physicalCoreCount())
            + " logical=" + str(self.logicalCoreCount())
            + " numa=" + str(_numaNodeCount)
            + " caches=" + str(_caches.length())
    }

    CpuTopology copy() {
        return new CpuTopology(_cores, _caches, _features,
            _socketCount, _numaNodeCount)
    }
}
```
