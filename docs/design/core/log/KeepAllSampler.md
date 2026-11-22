# `KeepAllSampler`

| 项 | 值 |
| --- | --- |
| 类型 | `class KeepAllSampler implements Sampler` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | `Sampler`、`LogRecord` |

---

## 1. 定位

默认采样器：保留所有已通过级别与过滤的记录。

不做：每 N 条采样、过滤、脱敏。

---

## 2. 设计逻辑

- 无字段；`keep` 恒返回 `true`。
- 是 `Logger` 的默认 sampler；`withSampler` 可替换。
- 无状态；可共享。

---

## 3. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `KeepAllSampler()` | 无 | 无 | 无 |

---

## 4. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `keep` | 恒保留 | `LogRecord record` | `Bool` | 无 |

---

## 5. 示例与反例

正确：`new KeepAllSampler()` 作为默认值。

反例：期望它采样；把它当过滤器；在 pipeline 外直接调用。

---

## 6. 测试/场景义务

恒 true；默认 Logger 使用；替换后原 Logger 不变；无状态/可共享。

---

## 7. XNull 伪代码

```xnull
class KeepAllSampler implements Sampler {
    KeepAllSampler() {
    }

    Bool keep(LogRecord record) {
        return true
    }
}
```
