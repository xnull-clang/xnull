# `CpuCore`

| 项 | 值 |
| --- | --- |
| 类型 | `class CpuCore` |
| 包 | `xdk.os.cpu` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

一个逻辑 CPU 的拓扑条目：id、socket、core、thread、NUMA 节点、频率、在线状态。

不做：调度、绑核、性能计数、温度。

---

## 2. 设计逻辑

- 逻辑 CPU 用 `id` 标识；`socket/core/thread` 表示拓扑。
- `threadId` 是同一物理核内的线程号（SMT）；无 SMT 时为 0。
- `frequencyMhz` 是当前/标称频率快照；0 表示未知。
- `isOnline` 表示 OS 当前可见/在线。
- 值语义快照；不可变。
- 不保证 id 连续；容器内 id 可能被重映射。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_id` | `Int` | final | ≥0 |
| `_socketId` | `Int` | final | ≥0 |
| `_coreId` | `Int` | final | ≥0 |
| `_threadId` | `Int` | final | ≥0 |
| `_numaNodeId` | `Int` | final | ≥0 |
| `_frequencyMhz` | `Int` | final | ≥0；0=未知 |
| `_isOnline` | `Bool` | final | 是否在线 |

不变量：所有 id/频率 ≥0；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CpuCore(...)` | 7 个字段 | id/socket/core/thread/numa/frequency ≥0 | 负值 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `id` | 逻辑 CPU id | 无 | `Int` | 无 |
| `socketId` | socket | 无 | `Int` | 无 |
| `coreId` | 物理核 | 无 | `Int` | 无 |
| `threadId` | 线程号 | 无 | `Int` | 无 |
| `numaNodeId` | NUMA 节点 | 无 | `Int` | 无 |
| `frequencyMhz` | 频率 | 无 | `Int` | 无 |
| `isOnline` | 是否在线 | 无 | `Bool` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `CpuCore other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `CpuCore` | 无 |

---

## 8. 使用的技术

- 不可变值快照；
- 拓扑字段；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、Int、Bool、String；
- 运行时/适配器：CPU 拓扑读取；
- 接口：`CpuTopology`。

---

## 10. 依赖的特性/接口/类

`CpuTopology`、`CpuCache`、`CpuAffinity`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：`equals` 字段比较；`==` 仍是引用身份；可作 `Map` 键（不推荐）。

---

## 12. 示例与反例

正确：`core.numaNodeId()` 用于 NUMA 绑定；`core.socketId()`/`coreId()` 用于拓扑展示。  
反例：假设 id 连续；把 `threadId` 当全局线程 id；容器内假设 host CPU 全可见。

---

## 13. 测试/场景义务

字段非负；SMT/无 SMT；多 socket；NUMA；离线 CPU；id 不连续；equals/copy；容器可见 CPU。

---

## 14. XNull 伪代码

```xnull
class CpuCore {
    final Int _id
    final Int _socketId
    final Int _coreId
    final Int _threadId
    final Int _numaNodeId
    final Int _frequencyMhz
    final Bool _isOnline

    CpuCore(Int id, Int socketId, Int coreId, Int threadId,
            Int numaNodeId, Int frequencyMhz, Bool isOnline) {
        if id < 0 || socketId < 0 || coreId < 0 || threadId < 0
            || numaNodeId < 0 || frequencyMhz < 0 {
            throw "CpuCore: negative field"
        }
        _id = id
        _socketId = socketId
        _coreId = coreId
        _threadId = threadId
        _numaNodeId = numaNodeId
        _frequencyMhz = frequencyMhz
        _isOnline = isOnline
    }

    Int id() { return _id }
    Int socketId() { return _socketId }
    Int coreId() { return _coreId }
    Int threadId() { return _threadId }
    Int numaNodeId() { return _numaNodeId }
    Int frequencyMhz() { return _frequencyMhz }
    Bool isOnline() { return _isOnline }

    String describe() {
        return "cpu " + str(_id)
            + " socket=" + str(_socketId)
            + " core=" + str(_coreId)
            + " thread=" + str(_threadId)
            + " numa=" + str(_numaNodeId)
            + " mhz=" + str(_frequencyMhz)
    }

    Bool equals(CpuCore other) {
        if other == null { return false }
        return _id == other.id()
            && _socketId == other.socketId()
            && _coreId == other.coreId()
            && _threadId == other.threadId()
            && _numaNodeId == other.numaNodeId()
            && _frequencyMhz == other.frequencyMhz()
            && _isOnline == other.isOnline()
    }

    CpuCore copy() {
        return new CpuCore(_id, _socketId, _coreId, _threadId,
            _numaNodeId, _frequencyMhz, _isOnline)
    }
}
```
