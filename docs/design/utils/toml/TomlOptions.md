# `TomlOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class TomlOptions` |
| 包 | `xdk.toml` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

TOML 解析/生成选项：最大深度、最大字节。

不做：重复键开关、日期时间开关、缩进宽度、注释保留、Schema、流式配置。

---

## 2. 设计逻辑

- 可变 builder；`Toml.parse`/`Toml.stringify` 在入口复制，后续修改不影响已开始调用。
- 默认：深度 128、16 MiB。
- 不提供 `allowDuplicateKeys`：TOML 规定重复键/重复表非法，开启重复键没有合法语义。
- `maxDepth`/`maxBytes` 必须 >0；非法值 panic，避免把无效预算传入解析器。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_maxDepth` | `Int` | 表/数组/内联表最大嵌套深度，根表为 1 |
| `_maxBytes` | `Long` | 解析输入/生成输出的 UTF-8 字节上限 |

不变量：`_maxDepth > 0`；`_maxBytes > 0`。

---

## 4. 生命周期

可变；无 close；`copy` 返回独立快照。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TomlOptions()` | 无 | 默认值 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `maxDepth` | 设置深度 | `Int value` | `TomlOptions` | ≤0 → panic |
| `maxBytes` | 设置字节上限 | `Long value` | `TomlOptions` | ≤0 → panic |
| `getMaxDepth` | 读取深度 | 无 | `Int` | 无 |
| `getMaxBytes` | 读取字节上限 | 无 | `Long` | 无 |
| `copy` | 独立快照 | 无 | `TomlOptions` | 无 |

说明：

- `maxDepth` 统计表、数组、内联表层级；根表为 1，标量值不额外增加深度。
- `maxBytes` 在解析时限制输入 UTF-8 字节，在生成时限制输出 UTF-8 字节；不是字符数。
- 深度/字节超限在解析中返回 `InvalidArgument`；不返回部分树。

---

## 8. 使用的技术

- 可变 builder；
- 有界预算。

---

## 9. 需要的支撑

- 语言：class、Int、Long；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

可变；非线程安全；无资源。调用方负责在跨任务共享前完成配置；`Toml` 入口会复制，之后不再读取原对象。

---

## 12. 示例与反例

正确：`new TomlOptions().maxDepth(64).maxBytes(1048576)`。  
反例：`maxDepth(0)` 或 `maxBytes(0)`。  
反例：寻找 `allowDuplicateKeys(true)`；TOML 重复键始终非法。  
反例：修改已传入 `Toml.parse` 的 options 并期望正在进行的解析变化。

---

## 13. 测试/场景义务

- 默认值；
- 每个 setter/getter；
- 非正深度/字节 panic；
- `copy` 独立；
- 入口复制：调用后修改 options 不影响结果；
- `maxDepth` 根/嵌套表/嵌套数组边界；
- `maxBytes` 多字节 UTF-8 计数；
- 解析/生成超限失败。

---

## 14. XNull 伪代码

```xnull
class TomlOptions {
    Int _maxDepth = 128
    Long _maxBytes = 16777216

    TomlOptions() {
    }

    TomlOptions maxDepth(Int value) {
        if value <= 0 { throw "TomlOptions.maxDepth: invalid" }
        _maxDepth = value
        return self
    }

    TomlOptions maxBytes(Long value) {
        if value <= 0 { throw "TomlOptions.maxBytes: invalid" }
        _maxBytes = value
        return self
    }

    Int getMaxDepth() { return _maxDepth }
    Long getMaxBytes() { return _maxBytes }

    TomlOptions copy() {
        TomlOptions result = new TomlOptions()
        result.maxDepth(_maxDepth)
        result.maxBytes(_maxBytes)
        return result
    }
}
```
