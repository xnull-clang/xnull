# `BackpressurePolicy`

| 项 | 值 |
| --- | --- |
| 类型 | `class BackpressurePolicy` |
| 包 | `xdk.net.service` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

服务端背压策略：活动连接水位、待接受连接水位、读取缓冲水位、满水位时暂停还是拒绝。

不做：写队列、消息丢弃、拥塞控制、TCP 窗口调优、客户端重连、跨连接公平调度。

本包不建立无界应用层写队列；写侧背压由 TCP 发送窗口与 `ServiceOptions.writeTimeoutMillis` 提供。`BackpressurePolicy` 只控制**接受**与**读取**两个 admission 点，避免把慢消费者变成内存增长。

---

## 2. 设计逻辑

- 可变 builder；`Server` 绑定时复制。
- 两级水位：
  - 连接水位：活动连接数达到 `acceptHighWaterConnections` 时暂停接受；降到 `acceptLowWaterConnections` 后恢复。
  - 待接受水位：已接受但尚未分派的连接数达到 `pendingAcceptHighWater` 时暂停接受；降到 `pendingAcceptLowWater` 后恢复。
- 读取水位：运行时若有分派缓冲，达到 `readHighWaterBytes` 时暂停读取，降到 `readLowWaterBytes` 后恢复。
- `rejectOnHighWater=true` 时不做暂停，而是接受后立即以 `Busy` 关闭，并计入拒绝统计；用于“快速失败”场景。
- 0 表示禁用软水位：连接水位为 0 时由 `ServiceOptions.maxConnections` 硬上限约束；待接受水位为 0 时由 `ServiceOptions.acceptQueueCapacity` 硬上限约束。
- 不静默丢弃；满水位要么暂停，要么显式拒绝并记录。
- 无 close；非线程安全（builder 阶段）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_acceptHighWaterConnections` | `Int` | 活动连接高水位；0=禁用 |
| `_acceptLowWaterConnections` | `Int` | 活动连接低水位；高水位>0 时必须 < 高水位 |
| `_pendingAcceptHighWater` | `Int` | 待接受高水位；0=使用队列硬上限 |
| `_pendingAcceptLowWater` | `Int` | 待接受低水位；必须 < 高水位 |
| `_readHighWaterBytes` | `Long` | 读取缓冲高水位，>0 |
| `_readLowWaterBytes` | `Long` | 读取缓冲低水位，>0 且 < 高水位 |
| `_rejectOnHighWater` | `Bool` | 满水位时拒绝而非暂停 |
| `_pauseReads` | `Bool` | 读取高水位时是否暂停读取 |

不变量：连接水位成对为 0 或 `0 < low < high`；待接受水位为 0/0 或 `0 <= low < high`；`0 < readLow < readHigh`；布尔字段无隐含组合。

---

## 4. 生命周期

构造后可变；`Server` 绑定时复制；无 close；副本独立。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BackpressurePolicy()` | 无 | 默认值 | 无 |
| `BackpressurePolicy(BackpressurePolicy other)` | 非 null | 非 null | null → panic |

setter 的合法域见 §7；非法值是合同错误（panic）。设置连接/待接受水位时先设高水位，再设低水位；调整读取水位时先设低水位，再设高水位。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `acceptHighWaterConnections` | 活动连接高水位 | `Int value` | `BackpressurePolicy` | <0 → panic；与低水位冲突 → panic |
| `acceptLowWaterConnections` | 活动连接低水位 | `Int value` | `BackpressurePolicy` | <0 → panic；与高水位冲突 → panic |
| `pendingAcceptHighWater` | 待接受高水位 | `Int value` | `BackpressurePolicy` | <0 → panic；与低水位冲突 → panic |
| `pendingAcceptLowWater` | 待接受低水位 | `Int value` | `BackpressurePolicy` | <0 → panic；与高水位冲突 → panic |
| `readHighWaterBytes` | 读取高水位 | `Long value` | `BackpressurePolicy` | ≤0/≤低水位 → panic |
| `readLowWaterBytes` | 读取低水位 | `Long value` | `BackpressurePolicy` | ≤0/≥高水位 → panic |
| `rejectOnHighWater` | 满水位拒绝 | `Bool value` | `BackpressurePolicy` | 无 |
| `pauseReads` | 读取暂停开关 | `Bool value` | `BackpressurePolicy` | 无 |
| `getAcceptHighWaterConnections` | 读高水位 | 无 | `Int` | 无 |
| `getAcceptLowWaterConnections` | 读低水位 | 无 | `Int` | 无 |
| `getPendingAcceptHighWater` | 读待接受高水位 | 无 | `Int` | 无 |
| `getPendingAcceptLowWater` | 读待接受低水位 | 无 | `Int` | 无 |
| `getReadHighWaterBytes` | 读读取高水位 | 无 | `Long` | 无 |
| `getReadLowWaterBytes` | 读读取低水位 | 无 | `Long` | 无 |
| `isRejectOnHighWater` | 是否拒绝 | 无 | `Bool` | 无 |
| `isPauseReads` | 是否暂停读取 | 无 | `Bool` | 无 |
| `shouldPauseAccept` | 是否应暂停接受 | `Int activeConnections, Int pendingAccepts` | `Bool` | 负值 → panic |
| `canResumeAccept` | 是否可恢复接受 | `Int activeConnections, Int pendingAccepts` | `Bool` | 负值 → panic |
| `shouldPauseReads` | 是否应暂停读取 | `Long bufferedBytes` | `Bool` | <0 → panic |
| `canResumeReads` | 是否可恢复读取 | `Long bufferedBytes` | `Bool` | <0 → panic |
| `copy` | 独立快照 | 无 | `BackpressurePolicy` | 无 |

说明：

- `shouldPauseAccept` 在 `rejectOnHighWater=true` 时返回 false；拒绝由运行时执行。
- 低水位 0 合法，表示“完全排空后恢复”；待接受水位 0/0 表示使用 `ServiceOptions.acceptQueueCapacity`。
- `canResumeAccept` 只在未暂停时返回 true；两个水位都禁用时返回 true。
- `readHighWaterBytes` 与 `readLowWaterBytes` 始终成对有效；`pauseReads=false` 时 `shouldPauseReads` 返回 false。
- 所有判断都是纯函数；不修改计数器。

---

## 8. 使用的技术

- 双水位滞回；
- 接受/读取 admission；
- 显式拒绝；
- 纯函数判定；
- builder 快照。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Bool；
- 运行时：无；
- 接口：`Server`、`ServiceOptions`、`ServiceStats`。

---

## 10. 依赖的特性/接口/类

`Server`、`ServiceOptions`、`ServiceStats`。

---

## 11. 所有权与并发

可变；非线程安全；`Server` 绑定时复制；无资源；副本独立。
相等：引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`new BackpressurePolicy().acceptHighWaterConnections(96).acceptLowWaterConnections(32).readHighWaterBytes(1048576).readLowWaterBytes(262144)`；达到 96 个活动连接时暂停接受，降到 32 后恢复。  
反例：低水位高于高水位；用 0 表示“立即拒绝”；期望策略自动扩容；期望满水位时静默丢消息；在 `rejectOnHighWater=true` 时仍等待暂停。

---

## 13. 测试/场景义务

默认值；每个 setter；非法/冲突；高水位触发；低水位恢复；待接受水位；读取水位；拒绝模式；暂停模式；`pauseReads=false`；水位边界（等于/大于/小于）；copy 独立；与 `ServiceOptions` 硬上限组合。

---

## 14. XNull 伪代码

```xnull
class BackpressurePolicy {
    Int _acceptHighWaterConnections = 0
    Int _acceptLowWaterConnections = 0
    Int _pendingAcceptHighWater = 0
    Int _pendingAcceptLowWater = 0
    Long _readHighWaterBytes = 1048576
    Long _readLowWaterBytes = 262144
    Bool _rejectOnHighWater = false
    Bool _pauseReads = true

    BackpressurePolicy() {
    }

    BackpressurePolicy(BackpressurePolicy other) {
        if other == null { throw "BackpressurePolicy: null other" }
        _acceptHighWaterConnections = other.getAcceptHighWaterConnections()
        _acceptLowWaterConnections = other.getAcceptLowWaterConnections()
        _pendingAcceptHighWater = other.getPendingAcceptHighWater()
        _pendingAcceptLowWater = other.getPendingAcceptLowWater()
        _readHighWaterBytes = other.getReadHighWaterBytes()
        _readLowWaterBytes = other.getReadLowWaterBytes()
        _rejectOnHighWater = other.isRejectOnHighWater()
        _pauseReads = other.isPauseReads()
    }

    BackpressurePolicy acceptHighWaterConnections(Int value) {
        if value < 0 { throw "BackpressurePolicy.acceptHighWaterConnections: negative" }
        if value == 0 && _acceptLowWaterConnections > 0 {
            throw "BackpressurePolicy.acceptHighWaterConnections: low enabled"
        }
        if value > 0 && value <= _acceptLowWaterConnections {
            throw "BackpressurePolicy.acceptHighWaterConnections: below low"
        }
        _acceptHighWaterConnections = value
        return self
    }

    BackpressurePolicy acceptLowWaterConnections(Int value) {
        if value < 0 { throw "BackpressurePolicy.acceptLowWaterConnections: negative" }
        if _acceptHighWaterConnections == 0 && value > 0 {
            throw "BackpressurePolicy.acceptLowWaterConnections: high disabled"
        }
        if _acceptHighWaterConnections > 0 && value >= _acceptHighWaterConnections {
            throw "BackpressurePolicy.acceptLowWaterConnections: not below high"
        }
        _acceptLowWaterConnections = value
        return self
    }

    BackpressurePolicy pendingAcceptHighWater(Int value) {
        if value < 0 { throw "BackpressurePolicy.pendingAcceptHighWater: negative" }
        if value == 0 && _pendingAcceptLowWater > 0 {
            throw "BackpressurePolicy.pendingAcceptHighWater: low enabled"
        }
        if value > 0 && value <= _pendingAcceptLowWater {
            throw "BackpressurePolicy.pendingAcceptHighWater: below low"
        }
        _pendingAcceptHighWater = value
        return self
    }

    BackpressurePolicy pendingAcceptLowWater(Int value) {
        if value < 0 { throw "BackpressurePolicy.pendingAcceptLowWater: negative" }
        if _pendingAcceptHighWater == 0 && value > 0 {
            throw "BackpressurePolicy.pendingAcceptLowWater: high disabled"
        }
        if _pendingAcceptHighWater > 0 && value >= _pendingAcceptHighWater {
            throw "BackpressurePolicy.pendingAcceptLowWater: not below high"
        }
        _pendingAcceptLowWater = value
        return self
    }

    BackpressurePolicy readHighWaterBytes(Long value) {
        if value <= 0 { throw "BackpressurePolicy.readHighWaterBytes: invalid" }
        if value <= _readLowWaterBytes {
            throw "BackpressurePolicy.readHighWaterBytes: below low"
        }
        _readHighWaterBytes = value
        return self
    }

    BackpressurePolicy readLowWaterBytes(Long value) {
        if value <= 0 { throw "BackpressurePolicy.readLowWaterBytes: invalid" }
        if value >= _readHighWaterBytes {
            throw "BackpressurePolicy.readLowWaterBytes: not below high"
        }
        _readLowWaterBytes = value
        return self
    }

    BackpressurePolicy rejectOnHighWater(Bool value) {
        _rejectOnHighWater = value
        return self
    }

    BackpressurePolicy pauseReads(Bool value) {
        _pauseReads = value
        return self
    }

    Int getAcceptHighWaterConnections() { return _acceptHighWaterConnections }
    Int getAcceptLowWaterConnections() { return _acceptLowWaterConnections }
    Int getPendingAcceptHighWater() { return _pendingAcceptHighWater }
    Int getPendingAcceptLowWater() { return _pendingAcceptLowWater }
    Long getReadHighWaterBytes() { return _readHighWaterBytes }
    Long getReadLowWaterBytes() { return _readLowWaterBytes }
    Bool isRejectOnHighWater() { return _rejectOnHighWater }
    Bool isPauseReads() { return _pauseReads }

    Bool shouldPauseAccept(Int activeConnections, Int pendingAccepts) {
        if activeConnections < 0 || pendingAccepts < 0 {
            throw "BackpressurePolicy.shouldPauseAccept: negative"
        }
        if _rejectOnHighWater { return false }
        if _acceptHighWaterConnections > 0
            && activeConnections >= _acceptHighWaterConnections {
            return true
        }
        if _pendingAcceptHighWater > 0
            && pendingAccepts >= _pendingAcceptHighWater {
            return true
        }
        return false
    }

    Bool canResumeAccept(Int activeConnections, Int pendingAccepts) {
        if activeConnections < 0 || pendingAccepts < 0 {
            throw "BackpressurePolicy.canResumeAccept: negative"
        }
        if _acceptHighWaterConnections > 0
            && activeConnections > _acceptLowWaterConnections {
            return false
        }
        if _pendingAcceptHighWater > 0
            && pendingAccepts > _pendingAcceptLowWater {
            return false
        }
        return true
    }

    Bool shouldPauseReads(Long bufferedBytes) {
        if bufferedBytes < 0 {
            throw "BackpressurePolicy.shouldPauseReads: negative"
        }
        if !_pauseReads { return false }
        return bufferedBytes >= _readHighWaterBytes
    }

    Bool canResumeReads(Long bufferedBytes) {
        if bufferedBytes < 0 {
            throw "BackpressurePolicy.canResumeReads: negative"
        }
        if !_pauseReads { return true }
        return bufferedBytes <= _readLowWaterBytes
    }

    BackpressurePolicy copy() {
        return new BackpressurePolicy(self)
    }
}
```
