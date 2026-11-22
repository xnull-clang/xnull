# `Sampler`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Sampler` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | `LogRecord` |

---

## 1. 定位

日志采样协议：在过滤之后、脱敏/写 sink 之前决定是否保留记录。

不做：级别阈值、过滤、脱敏、格式化、写 sink。

---

## 2. 设计逻辑

- 最小协议：`Bool keep(LogRecord record)`。
- 管道顺序固定：级别阈值 → `Filter.allow` → `Sampler.keep` → `Redactor` → `Sink`。
- 采样器可持有可变计数；同一实例被派生 Logger 共享时，计数也共享。
- `record == null` → `false`；不修改记录。
- 采样器只看到已通过级别与过滤的记录。

---

## 3. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `keep` | 是否保留 | `LogRecord record` | `Bool` | null → false |

---

## 4. 生命周期

协议无构造；实现由调用方创建；无 close；可变实现非线程安全。

---

## 5. 所有权与并发

不拥有记录；可共享；计数状态由实现声明；默认单 logger 使用。

---

## 6. 示例与反例

正确：`logger.withSampler(new EveryNSampler(10))`。

反例：在 sampler 里写 sink；过滤前采样；期望不同 Logger 共享计数但实例不同；null record 进入 redactor。

---

## 7. 测试/场景义务

保留/丢弃两侧；只统计已通过级别+过滤的记录；null record；与 filter/redactor 顺序组合；派生 Logger 共享同一实例的计数语义。

---

## 8. XNull 伪代码

```xnull
protocol Sampler {
    Bool keep(LogRecord record);
}
```
