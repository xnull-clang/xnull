# `TraceOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class TraceOptions` |
| 包 | `xdk.trace` |
| 稳定性 | `preview` |
| 依赖 | `Sampler` |

---

## 1. 定位

`Tracer` 的构建选项：服务名、采样器、单 span 属性上限、单 span 事件上限。

不做：导出器配置、传播器选择、资源/属性自动发现、动态重配置。

---

## 2. 设计逻辑

- builder 风格：setter 返回 `self`，可链式；getter 读取当前值。
- 默认值：服务名 `unknown_service`、`Sampler.alwaysOn()`、`maxAttributes=128`、`maxEvents=128`。
- `serviceName` 去首尾空白后必须 1..255 字符。
- `maxAttributes`/`maxEvents` 范围 0..1024；0 表示禁用对应记录，超过上限 panic。
- `copy()` 产生独立可变对象；`Sampler` 不可变，可共享。
- `Tracer.create` 会复制 options；创建后修改原 options 不影响 tracer。
- 可变 builder；非线程安全；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_serviceName` | `String` | 默认 `unknown_service` |
| `_sampler` | `Sampler` | 默认 alwaysOn |
| `_maxAttributes` | `Int` | 0..1024，默认 128 |
| `_maxEvents` | `Int` | 0..1024，默认 128 |

不变量：serviceName 非空且 ≤255；sampler 非 null；两个上限在 0..1024；builder 可重复设置，最后一次生效。

---

## 4. 生命周期

构造后可变；可多次 `copy`；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TraceOptions()` | 无 | 默认值 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `serviceName` | 设置服务名 | `String` | `TraceOptions` | null/空/超长 → panic |
| `sampler` | 设置采样器 | `Sampler` | `TraceOptions` | null → panic |
| `maxAttributes` | 设置属性上限 | `Int` | `TraceOptions` | <0 或 >1024 → panic |
| `maxEvents` | 设置事件上限 | `Int` | `TraceOptions` | <0 或 >1024 → panic |
| `getServiceName` | 读取服务名 | 无 | `String` | 无 |
| `getSampler` | 读取采样器 | 无 | `Sampler` | 无 |
| `getMaxAttributes` | 读取属性上限 | 无 | `Int` | 无 |
| `getMaxEvents` | 读取事件上限 | 无 | `Int` | 无 |
| `copy` | 独立快照 | 无 | `TraceOptions` | 无 |

说明：

- `serviceName` 使用 `trim` 后的值；空串和全空白非法。
- `maxAttributes=0` 表示 span 不记录属性；`maxEvents=0` 表示不记录事件。
- `copy()` 复制标量并共享不可变 `Sampler`。
- 不提供 `propagator` 字段；传播器由 `Tracer.create` 重载显式传入。

---

## 8. 使用的技术

- builder 模式；
- 默认值与上限校验；
- 快照复制。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool、`trim`；
- 运行时：无；
- 接口：`Sampler`。

---

## 10. 依赖的特性/接口/类

`Sampler`。

---

## 11. 所有权与并发

可变；非线程安全；调用方应在跨任务共享前 `copy` 或交给 `Tracer.create` 复制；无资源。

---

## 12. 示例与反例

正确：

```text
TraceOptions options = new TraceOptions()
    .serviceName("orders")
    .sampler(Sampler.ratio(0.1))
    .maxAttributes(64)
    .maxEvents(32)
TraceOptions snapshot = options.copy()
```

反例：`maxAttributes(-1)`；`serviceName("   ")`；把 options 共享给多个线程同时改；创建 tracer 后修改 options 期望生效。

---

## 13. 测试/场景义务

默认值；每个 setter；链式返回；非法服务名；上限 0/1024/1025；sampler null；`copy` 独立性；修改原对象不影响副本；`Tracer.create` 后 options 变化不影响 tracer。

---

## 14. XNull 伪代码

```xnull
class TraceOptions {
    String _serviceName = "unknown_service"
    Sampler _sampler = Sampler.alwaysOn()
    Int _maxAttributes = 128
    Int _maxEvents = 128

    TraceOptions() {
    }

    TraceOptions serviceName(String value) {
        if value == null { throw "TraceOptions.serviceName: null" }
        String normalized = trim(value)
        if normalized.length() == 0 || normalized.length() > 255 {
            throw "TraceOptions.serviceName: invalid"
        }
        _serviceName = normalized
        return self
    }

    TraceOptions sampler(Sampler value) {
        if value == null { throw "TraceOptions.sampler: null" }
        _sampler = value
        return self
    }

    TraceOptions maxAttributes(Int value) {
        if value < 0 || value > 1024 {
            throw "TraceOptions.maxAttributes: outside 0..1024"
        }
        _maxAttributes = value
        return self
    }

    TraceOptions maxEvents(Int value) {
        if value < 0 || value > 1024 {
            throw "TraceOptions.maxEvents: outside 0..1024"
        }
        _maxEvents = value
        return self
    }

    String getServiceName() { return _serviceName }
    Sampler getSampler() { return _sampler }
    Int getMaxAttributes() { return _maxAttributes }
    Int getMaxEvents() { return _maxEvents }

    TraceOptions copy() {
        TraceOptions result = new TraceOptions()
        result.serviceName(_serviceName)
        result.sampler(_sampler)
        result.maxAttributes(_maxAttributes)
        result.maxEvents(_maxEvents)
        return result
    }
}
```
