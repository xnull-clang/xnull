# `HeartbeatPolicy`

| 项 | 值 |
| --- | --- |
| 类型 | `class HeartbeatPolicy` |
| 包 | `xdk.net.service` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

连接/会话空闲检测策略：检查节奏、空闲超时、从最后活动时间计算截止。

不做：协议心跳帧、ping/pong、TCP keepalive 设置、重连、会话恢复、健康检查端点。

本类型只定义**空闲多久算失活**；它不向连接写入任何字节。WebSocket 的 ping/pong 仍由 `xdk.net.websocket` 负责；TCP keepalive 仍由 `SocketOptions.keepAlive` 负责。

---

## 2. 设计逻辑

- 可变 builder；`ServiceOptions` 构造/复制时持有独立副本。
- `intervalMillis=0` 表示禁用；`timeoutMillis` 默认 30s；启用时要求 `timeout >= interval`。
- `Session.run` 可用 `timeoutMillis` 设置每次读取的截止时间，从而在没有计时器任务的情况下检测空闲。
- `intervalMillis` 供服务运行时安排周期检查；它不改变协议行为。
- `isExpired`/`deadlineFrom` 为纯计算；不读取时钟。
- 无 close；非线程安全（builder 阶段）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_intervalMillis` | `Long` | 检查间隔；0=禁用；≥0 |
| `_timeoutMillis` | `Long` | 空闲超时；>0；启用时 ≥interval |

不变量：`interval >= 0`；`timeout > 0`；`interval > 0` 时 `timeout >= interval`；禁用时仍保留 timeout 值但不生效。

---

## 4. 生命周期

构造后可变；`ServiceOptions` 复制；无 close；副本独立。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HeartbeatPolicy()` | 无 | 默认禁用、30s | 无 |
| `HeartbeatPolicy(HeartbeatPolicy other)` | 非 null | 非 null | null → panic |

setter 的合法域见 §7；非法值是合同错误（panic）。扩大 `intervalMillis` 超过当前 timeout 时，先提高 `timeoutMillis`；缩小 timeout 低于当前 interval 时，先缩小 interval。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `intervalMillis` | 设置检查间隔 | `Long value` | `HeartbeatPolicy` | <0/与超时冲突 → panic |
| `timeoutMillis` | 设置空闲超时 | `Long value` | `HeartbeatPolicy` | ≤0/小于间隔 → panic |
| `getIntervalMillis` | 读检查间隔 | 无 | `Long` | 无 |
| `getTimeoutMillis` | 读空闲超时 | 无 | `Long` | 无 |
| `isEnabled` | 是否启用 | 无 | `Bool` | 无 |
| `deadlineFrom` | 计算截止 | `Long lastActivityMonoMillis` | `Long` | <0 → panic |
| `isExpired` | 是否空闲超时 | `Long nowMonoMillis, Long lastActivityMonoMillis` | `Bool` | 负值 → panic |
| `copy` | 独立快照 | 无 | `HeartbeatPolicy` | 无 |

说明：

- `intervalMillis(0)` 禁用；此时不要求 `timeout >= interval`，但 timeout 仍须 >0。
- `deadlineFrom` 返回 `lastActivityMonoMillis + timeoutMillis`；禁用时也返回该值，调用方应先检查 `isEnabled`。
- `isExpired` 在禁用时恒为 false；否则 `now >= lastActivity + timeout`。
- 单调毫秒由运行时提供；不接受墙上时钟，避免回拨。
- 不发送任何帧；不接受/不校验对端心跳。

---

## 8. 使用的技术

- 单调时间；
- 空闲截止；
- 纯函数判定；
- builder 快照。

---

## 9. 需要的支撑

- 语言：class、Long、Bool；
- 运行时：`monotonicMillis`（调用方提供）；
- 接口：`Session`、`ServiceOptions`、`ServiceStats`。

---

## 10. 依赖的特性/接口/类

`Session`、`ServiceOptions`、`ServiceStats`、`monotonicMillis`。

---

## 11. 所有权与并发

可变；非线程安全；`ServiceOptions` 复制；无资源；副本独立。
相等：引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`new HeartbeatPolicy().intervalMillis(15000).timeoutMillis(45000)`；`Session.run` 用 45s 作为读截止，45s 无数据即 `Timeout`。  
反例：期望策略自动发 ping；把 `intervalMillis` 当超时；设置 `timeout < interval`；用墙上时钟；禁用时仍按超时关闭连接；把本策略与 WebSocket ping/pong 混用。

---

## 13. 测试/场景义务

默认值；禁用/启用；interval 与 timeout 边界；非法值；`deadlineFrom`；`isExpired` 等于/大于/小于截止；copy 独立；与 `Session.run` 读截止组合；与 `ServiceOptions.idleTimeoutMillis` 的优先级；取消不误判为空闲。

---

## 14. XNull 伪代码

```xnull
class HeartbeatPolicy {
    Long _intervalMillis = 0
    Long _timeoutMillis = 30000

    HeartbeatPolicy() {
    }

    HeartbeatPolicy(HeartbeatPolicy other) {
        if other == null { throw "HeartbeatPolicy: null other" }
        _intervalMillis = other.getIntervalMillis()
        _timeoutMillis = other.getTimeoutMillis()
    }

    HeartbeatPolicy intervalMillis(Long value) {
        if value < 0 { throw "HeartbeatPolicy.intervalMillis: negative" }
        if value > 0 && value > _timeoutMillis {
            throw "HeartbeatPolicy.intervalMillis: exceeds timeout"
        }
        _intervalMillis = value
        return self
    }

    HeartbeatPolicy timeoutMillis(Long value) {
        if value <= 0 { throw "HeartbeatPolicy.timeoutMillis: invalid" }
        if _intervalMillis > 0 && value < _intervalMillis {
            throw "HeartbeatPolicy.timeoutMillis: below interval"
        }
        _timeoutMillis = value
        return self
    }

    Long getIntervalMillis() { return _intervalMillis }
    Long getTimeoutMillis() { return _timeoutMillis }

    Bool isEnabled() {
        return _intervalMillis > 0
    }

    Long deadlineFrom(Long lastActivityMonoMillis) {
        if lastActivityMonoMillis < 0 {
            throw "HeartbeatPolicy.deadlineFrom: negative"
        }
        return lastActivityMonoMillis + _timeoutMillis
    }

    Bool isExpired(Long nowMonoMillis, Long lastActivityMonoMillis) {
        if nowMonoMillis < 0 || lastActivityMonoMillis < 0 {
            throw "HeartbeatPolicy.isExpired: negative"
        }
        if !self.isEnabled() { return false }
        return nowMonoMillis >= lastActivityMonoMillis + _timeoutMillis
    }

    HeartbeatPolicy copy() {
        return new HeartbeatPolicy(self)
    }
}
```
