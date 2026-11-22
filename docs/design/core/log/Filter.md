# `Filter`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Filter` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | `LogRecord` |

---

## 1. 定位

日志记录过滤器：在级别阈值之后、采样/脱敏/写 sink 之前决定是否保留记录。

不做：级别阈值（`Logger` 负责）、格式化、写 sink、异步队列。

---

## 2. 设计逻辑

- 最小协议：`allow(LogRecord record)`。
- 管道顺序固定：级别阈值 → `Filter.allow` → `Sampler.keep` → `Redactor` → `Sink`。
- 过滤器不修改记录；拒绝的记录不进入采样、脱敏或 sink。
- 实现可持有调用方提供的 predicate；不得读取全局状态。
- 非线程安全由实现声明；默认按单 logger 使用。

---

## 3. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `allow` | 是否保留 | `LogRecord record` | `Bool` | record 为 null → `false` |

---

## 4. 生命周期

协议无构造；实现由调用方创建；无 close；可随 Logger 共享。

---

## 5. 所有权与并发

过滤器由 Logger 引用，不拥有记录；可共享；实现若持有可变状态则非线程安全。

---

## 6. 示例与反例

正确：`logger.withFilter(new PredicateFilter((LogRecord record) -> record.level() == Level.Error))`。

反例：在 `allow` 里写 sink；修改记录字段；把级别阈值重复塞进 Filter；拒绝后仍调用 sampler。

---

## 7. 测试/场景义务

允许/拒绝两侧；null record → false；拒绝不进入 sampler/redactor/sink；多个过滤器不叠加（Logger 只持有一个）；与 `KeepAllFilter` 默认行为一致。

---

## 8. XNull 伪代码

```xnull
protocol Filter {
    Bool allow(LogRecord record);
}
```
