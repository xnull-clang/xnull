# `Redactor`

| 项 | 值 |
| --- | --- |
| 类型 | `class Redactor` |
| 包 | `xdk.audit` |
| 稳定性 | `preview` |
| 依赖 | `Regex`、`AuditEvent` |

---

## 1. 定位

局部、可变的审计脱敏器：按插入顺序应用正则替换，脱敏字符串和审计事件。

不做：全局 PII 规则、通用日志脱敏器、结构化字段策略、加密/哈希、捕获组展开、策略持久化。

---

## 2. 设计逻辑

- 规则是 `(Regex, replacement)` 对，按加入顺序保存；使用平行列表保持对齐。
- 每次 `addPattern` 追加；允许重复规则；后一条规则看到前一条的输出。
- `redact` 在监视器内复制规则快照，释放锁后应用；规则变更不影响进行中的调用。
- `redactEvent` 脱敏 actor/action/resource/outcome 和字段值；字段键不改写。
- 替换是 `Regex.replaceAll` 的字面替换；不支持 `$1` 捕获组展开。
- 替换串必须非空，避免把 actor/action/outcome 脱敏成空串而破坏事件不变量。
- 无全局模式；每个实例独立；显式共享时修改对所有持有者可见。
- `clear` 清空规则；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_patterns` | `List<Regex>` | final；编译后的规则 |
| `_replacements` | `List<String>` | final；与 `_patterns` 一一对应，非空 |
| `_monitor` | `RuntimeMonitor` | final；保护规则列表 |

不变量：两个列表长度相等且索引对齐；pattern 非 null；replacement 非 null 且非空；顺序即插入顺序；所有规则变更在监视器内完成；无全局状态。

---

## 4. 生命周期

可变；无 close；可随时 `addPattern`/`clear`；规则存活到 `clear` 或实例回收。

可跨任务共享；无资源句柄；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Redactor()` | 无 | 空规则集 | 无 |

构造不注册任何默认规则；调用方必须显式添加。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `addPattern` | 追加规则 | `Regex pattern, String replacement` | `Redactor`（self） | null/空 replacement → panic |
| `redact` | 脱敏文本 | `String text` | `String` | null → panic |
| `redactEvent` | 脱敏事件 | `AuditEvent event` | `AuditEvent` | null → panic |
| `clear` | 清空规则 | 无 | `void` | 无 |

说明：

- `addPattern` 变异当前实例并返回 `self`，支持链式调用；不复制规则，不编译字符串。
- `pattern` 必须是已编译的 `Regex`；编译失败由调用方在 `Regex.compile` 处处理。
- `replacement` 为空串时 panic；用 `"[REDACTED]"` 等非空标记代替删除，保证必填字段仍非空。
- `redact` 按插入顺序应用全部规则；无匹配时返回原文本（或等值文本）。
- `redactEvent` 返回新事件；保留 `level` 和 `timestampMono`；字段键不变，字段值逐条脱敏。
- `redactEvent` 对所有字符串值使用同一规则快照，保证一次事件内的规则一致。
- `clear` 幂等；清空后 `redact` 返回原文。
- 共享 `Redactor` 时，一个持有者的 `addPattern`/`clear` 会影响其他持有者；需要隔离时创建独立实例。

---

## 8. 使用的技术

- 正则字面替换；
- 有序规则列表；
- 快照隔离；
- 不可变事件重建；
- 运行时监视器。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Map、String；
- 运行时：`RuntimeMonitor.enter/exit`、`Regex.replaceAll`；
- 接口：`Regex`、`AuditEvent`、`AuditLevel`。

---

## 10. 依赖的特性/接口/类

`Regex`、`AuditEvent`、`AuditLevel`、`RuntimeMonitor`、`Regex.replaceAll`。

---

## 11. 所有权与并发

引用语义；可变；线程安全；可跨任务共享。规则变更与 `redact`/`redactEvent` 可并发；进行中的调用使用开始时快照。无资源；无取消点。

`redactEvent` 不修改输入事件；返回新事件。`Regex` 不可变，可安全共享。

---

## 12. 示例与反例

正确：添加邮箱和 token 规则；`redact` 按顺序替换；`redactEvent` 脱敏字段值并保留 level/timestamp；用非空标记替换敏感串。  
反例：期望全局默认规则；期望 `$1` 捕获组展开；期望字段键被脱敏；修改输入事件；把未编译的字符串传给 `addPattern`；依赖未定义的规则顺序；用空替换把 actor 变成空串。

---

## 13. 测试/场景义务

`addPattern` 顺序；重复规则；`clear`；空规则；无匹配；多匹配；空 replacement 拒绝；`redactEvent` 的 actor/action/resource/outcome/字段值；字段键保持不变；level/timestamp 保留；null 参数；并发快照；共享实例的可见性；`Regex` 编译失败由调用方处理。

---

## 14. XNull 伪代码

```xnull
class Redactor {
    final RuntimeMonitor _monitor
    final List<Regex> _patterns
    final List<String> _replacements

    Redactor() {
        _monitor = new RuntimeMonitor()
        _patterns = []
        _replacements = []
    }

    Redactor addPattern(Regex pattern, String replacement) {
        if pattern == null { throw "Redactor.addPattern: null pattern" }
        if replacement == null || replacement == "" {
            throw "Redactor.addPattern: empty replacement"
        }
        _monitor.enter()
        _patterns.push(pattern)
        _replacements.push(replacement)
        _monitor.exit()
        return self
    }

    String redact(String text) {
        if text == null { throw "Redactor.redact: null text" }
        _monitor.enter()
        List<Regex> patterns = _patterns.copy()
        List<String> replacements = _replacements.copy()
        _monitor.exit()
        return self.apply(text, patterns, replacements)
    }

    AuditEvent redactEvent(AuditEvent event) {
        if event == null { throw "Redactor.redactEvent: null event" }
        _monitor.enter()
        List<Regex> patterns = _patterns.copy()
        List<String> replacements = _replacements.copy()
        _monitor.exit()
        Map<String, String> source = event.fields()
        Map<String, String> fields = [:]
        List<String> keys = source.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            fields.put(key, self.apply(source.getOr(key, ""), patterns, replacements))
            index = index + 1
        }
        return new AuditEvent(
            self.apply(event.actor(), patterns, replacements),
            self.apply(event.action(), patterns, replacements),
            self.apply(event.resource(), patterns, replacements),
            self.apply(event.outcome(), patterns, replacements),
            event.level(),
            event.timestampMono(),
            fields)
    }

    void clear() {
        _monitor.enter()
        _patterns.clear()
        _replacements.clear()
        _monitor.exit()
    }

    private String apply(String text, List<Regex> patterns,
                         List<String> replacements) {
        String result = text
        Int index = 0
        while index < patterns.length() {
            result = patterns.get(index).replaceAll(result, replacements.get(index))
            index = index + 1
        }
        return result
    }
}
```
