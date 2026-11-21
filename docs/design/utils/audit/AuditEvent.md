# `AuditEvent`

| 项 | 值 |
| --- | --- |
| 类型 | `class AuditEvent` |
| 包 | `xdk.audit` |
| 稳定性 | `preview` |
| 依赖 | `AuditLevel` |

---

## 1. 定位

不可变审计事件：单调时间戳、主体、动作、资源、结果、级别、键值字段；派生操作返回新事件。

不做：日志格式化、序列化、持久化、字段级类型、墙钟时间、事件关联 ID、签名/哈希链。

---

## 2. 设计逻辑

- 七个字段全部 `final`；构造时校验并复制 `fields`。
- `actor`/`action`/`outcome` 必须非空；`resource` 允许空串；`level` 非 null；`timestampMono ≥ 0`；field key 非空，value 非 null。
- `of` 是常规构造：Info + `nowMono()` + 空字段；完整构造器用于测试、重放和 sink 转换。
- `withField` 返回新事件；同名 key 替换；timestamp/level 不变。
- `withLevel` 返回新事件；timestamp/fields 不变。
- `describe` 是紧凑的人类可读摘要；不转义分隔符，不用于机器解析。
- 不可变；无 close；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_actor` | `String` | final | 非空主体 |
| `_action` | `String` | final | 非空动作 |
| `_resource` | `String` | final | 非 null；可为空串 |
| `_outcome` | `String` | final | 非空结果 |
| `_level` | `AuditLevel` | final | 非 null |
| `_timestampMono` | `Long` | final | ≥0；单调毫秒 |
| `_fields` | `Map<String,String>` | final | 防御性复制；key 非空，value 非 null |

不变量：全部字段 final；`fields` 不与外部共享；actor/action/outcome 非空；resource 可空；`with*` 不修改原事件。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AuditEvent(String actor, String action, String resource, String outcome, AuditLevel level, Long timestampMono, Map<String,String> fields)` | 全部 | actor/action/outcome 非空；resource 非 null 可空；level 非 null；timestamp ≥0；fields 非 null；key 非空；value 非 null | 非法 → panic |

说明：

- 常规创建优先用 `AuditEvent.of(...)`；完整构造器用于固定时间戳、重放和 sink 转换。
- 构造器复制字段表；调用方之后修改原 map 不影响事件。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `of` | 便捷构造 | `String actor, String action, String resource, String outcome` | `AuditEvent` | 非法 → panic |
| `timestampMono` | 单调时间戳 | 无 | `Long` | 无 |
| `actor` | 主体 | 无 | `String` | 无 |
| `action` | 动作 | 无 | `String` | 无 |
| `resource` | 资源 | 无 | `String` | 无 |
| `outcome` | 结果 | 无 | `String` | 无 |
| `level` | 级别 | 无 | `AuditLevel` | 无 |
| `fields` | 字段快照 | 无 | `Map<String,String>` | 无 |
| `withField` | 派生字段 | `String key, String value` | `AuditEvent` | 非法 → panic |
| `withLevel` | 派生级别 | `AuditLevel level` | `AuditEvent` | null → panic |
| `describe` | 紧凑摘要 | 无 | `String` | 无 |

说明：

- `of` 使用 `AuditLevel.Info`、`nowMono()` 和空字段。
- `fields()` 返回副本；修改返回值不影响事件。
- `withField` 在 key 已存在时替换值；不保证字段顺序。
- `withLevel` 只替换级别，不改变时间戳、主体、动作、资源、结果或字段。
- `describe` 包含级别、时间戳、actor、action、resource、outcome 和字段数；分隔符不转义。

---

## 8. 使用的技术

- 不可变快照；
- 防御性复制；
- 单调时间戳；
- 字符串拼接。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Long、Int、Bool、Map；
- 运行时：`nowMono`；
- 接口：`AuditLevel`。

---

## 10. 依赖的特性/接口/类

`AuditLevel`、`nowMono`、`Map`、`String`、`Long`。

---

## 11. 所有权与并发

引用语义但不可变；可跨任务共享；`fields()` 返回副本；无资源；无取消点。
相等：引用身份；值比较请比较各字段；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：`AuditEvent.of("alice","role.grant","project/42","success").withField("role","admin").withLevel(AuditLevel.Warning)`。  
反例：空 actor/action/outcome；null resource；修改 `fields()` 期望影响事件；期望 `withField` 原地修改；把 `describe` 当 JSON 解析；未脱敏就写入 token。

---

## 13. 测试/场景义务

构造校验；resource 空串合法；actor/action/outcome 空串非法；负时间戳；字段表复制；`withField` 新增/替换；`withLevel`；`of` 默认值；`describe`；null 参数；不可变性；空字段 key。

---

## 14. XNull 伪代码

```xnull
class AuditEvent {
    final String _actor
    final String _action
    final String _resource
    final String _outcome
    final AuditLevel _level
    final Long _timestampMono
    final Map<String, String> _fields

    AuditEvent(String actor, String action, String resource, String outcome,
               AuditLevel level, Long timestampMono, Map<String, String> fields) {
        if actor == null || actor == "" { throw "AuditEvent: empty actor" }
        if action == null || action == "" { throw "AuditEvent: empty action" }
        if resource == null { throw "AuditEvent: null resource" }
        if outcome == null || outcome == "" { throw "AuditEvent: empty outcome" }
        if level == null { throw "AuditEvent: null level" }
        if timestampMono < 0 { throw "AuditEvent: negative timestamp" }
        if fields == null { throw "AuditEvent: null fields" }
        _actor = actor
        _action = action
        _resource = resource
        _outcome = outcome
        _level = level
        _timestampMono = timestampMono
        _fields = [:]
        List<String> keys = fields.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if key == null || key == "" { throw "AuditEvent: empty field key" }
            String value = fields.getOr(key, "")
            if value == null { throw "AuditEvent: null field value" }
            _fields.put(key, value)
            index = index + 1
        }
    }

    static AuditEvent of(String actor, String action, String resource, String outcome) {
        return new AuditEvent(actor, action, resource, outcome,
            AuditLevel.Info, nowMono(), [:])
    }

    String actor() { return _actor }
    String action() { return _action }
    String resource() { return _resource }
    String outcome() { return _outcome }
    AuditLevel level() { return _level }
    Long timestampMono() { return _timestampMono }

    Map<String, String> fields() { return _fields.copy() }

    AuditEvent withField(String key, String value) {
        if key == null || key == "" { throw "AuditEvent.withField: empty key" }
        if value == null { throw "AuditEvent.withField: null value" }
        Map<String, String> next = _fields.copy()
        next.put(key, value)
        return new AuditEvent(_actor, _action, _resource, _outcome,
            _level, _timestampMono, next)
    }

    AuditEvent withLevel(AuditLevel level) {
        if level == null { throw "AuditEvent.withLevel: null level" }
        return new AuditEvent(_actor, _action, _resource, _outcome,
            level, _timestampMono, _fields)
    }

    String describe() {
        return str(_level) + " mono=" + str(_timestampMono)
            + " actor=" + _actor
            + " action=" + _action
            + " resource=" + _resource
            + " outcome=" + _outcome
            + " fields=" + str(_fields.length())
    }
}
```
