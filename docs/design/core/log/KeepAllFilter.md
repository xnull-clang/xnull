# `KeepAllFilter`

| 项 | 值 |
| --- | --- |
| 类型 | `class KeepAllFilter implements Filter` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | `Filter`、`LogRecord` |

---

## 1. 定位

默认过滤器：保留所有通过级别阈值的记录。

不做：条件过滤、采样、脱敏、sink。

---

## 2. 设计逻辑

- 无字段；`allow` 恒返回 `true`。
- 是 `Logger` 的默认过滤器；`withFilter` 可替换。
- 不读取全局状态；无资源。

---

## 3. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `KeepAllFilter()` | 无 | 无 | 无 |

---

## 4. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `allow` | 恒保留 | `LogRecord record` | `Bool` | 无 |

---

## 5. 示例与反例

正确：`new Logger("app", Level.Info).withFilter(new KeepAllFilter())`。

反例：把 KeepAllFilter 当“绕过级别阈值”；期望它过滤 null 记录之外的任何内容。

---

## 6. 测试/场景义务

恒 true；默认 Logger 使用；替换后原 Logger 不变；无状态/可共享。

---

## 7. XNull 伪代码

```xnull
class KeepAllFilter implements Filter {
    KeepAllFilter() {
    }

    Bool allow(LogRecord record) {
        return true
    }
}
```
