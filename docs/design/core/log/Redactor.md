# `Redactor`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Redactor` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

日志文本脱敏协议：在采样之后、写 sink 之前改写 message 与字段值。

不做：过滤、采样、格式化、写 sink。

---

## 2. 设计逻辑

- 最小协议：`String redact(String value)`。
- 管道顺序固定：级别阈值 → `Filter.allow` → `Sampler.keep` → `Redactor` → `Sink`。
- `Logger.log` 对 message 与每个 `Field.value` 调用同一个 redactor。
- `value == null` → 返回空串；不得返回 null。
- 脱敏不改变记录结构/字段数；只改文本值。

---

## 3. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `redact` | 改写文本 | `String value` | `String` | null → 空串 |

---

## 4. 生命周期

协议无构造；实现由调用方创建；无 close；可随 Logger 共享。

---

## 5. 所有权与并发

无资源；可共享；实现若持有可变状态则非线程安全。

---

## 6. 示例与反例

正确：`logger.withRedactor(new ReplaceRedactor("token=", "token=***"))`。

反例：在 redactor 里写 sink；返回 null；只改 message 漏掉字段值；用 redactor 代替过滤。

---

## 7. 测试/场景义务

message 与字段值都被改写；空 needle no-op；null 输入；redactor 不改变字段数量；与 filter/sampler 顺序组合。

---

## 8. XNull 伪代码

```xnull
protocol Redactor {
    String redact(String value);
}
```
