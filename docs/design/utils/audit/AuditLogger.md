# `AuditLogger`

| 项 | 值 |
| --- | --- |
| 类型 | `class AuditLogger` |
| 包 | `xdk.audit` |
| 稳定性 | `preview` |
| 依赖 | `AuditSink`、`AuditEvent`、`AuditLevel`、`Redactor`、`Error`、`RuntimeMonitor` |

---

## 1. 定位

同步审计入口：持有 sink，合并默认字段，应用脱敏，写事件；提供刷新和关闭。

不做：日志级别过滤、采样、异步队列、重试、格式化、文件轮转、全局 logger、多 sink 广播。

---

## 2. 设计逻辑

- 字段：`_sink`、`_redactor`、`_fields`、`_closed`、`_monitor`。
- 构造只校验 sink 非 null；不调用 `isOpen`，避免构造时的 TOCTOU。
- 可变 logger：`withField`/`withRedactor` 修改当前实例并返回 `self`；与 `AuditEvent` 的不可变派生明确不同。
- 选择变异而非派生：logger 拥有 sink 的关闭权；若 `withField` 复制 logger，多个实例共享同一 sink，close 所有权和关闭顺序会变得不明确。
- `log` 在监视器内完成：关闭检查、默认字段合并、脱敏、`sink.write`；原样返回 sink 结果。
- 默认字段只补事件缺失的 key；事件同名字段优先。
- 脱敏在合并后执行，覆盖 actor/action/resource/outcome 和字段值；字段键不变。
- `close`：置 closed → `sink.flush` → `sink.close`；flush 错误保留并返回；sink.close 为 `void`；重复 close 返回 `Ok(unit)`。
- `log`/`flush` 在关闭后返回 `Unavailable`；`with*` 在关闭后 panic。
- 线程安全：`RuntimeMonitor` 保护全部可变状态；sink 调用被串行化；禁止 sink/redactor 重入 logger。
- 无过滤、采样、异步、自动 flush、内部重试。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_sink` | `AuditSink` | final；非 null |
| `_redactor` | `Redactor?` | 可空；null 表示不脱敏 |
| `_fields` | `Map<String,String>` | 默认字段；key 非空，value 非 null |
| `_closed` | `Bool` | false→true 单向 |
| `_monitor` | `RuntimeMonitor` | final；保护状态与 sink 调用 |

不变量：sink/monitor 非 null；closed 单调；所有可变状态只在监视器内读写；sink 调用串行化；无重入。

---

## 4. 生命周期

构造后 open；可 `log`/`flush`/配置；`close` 后 closed。

`close` 幂等：第一次停止接受新事件、`flush`、`sink.close`；第二次返回 `Ok(unit)`。close 时即使 flush 失败也继续关闭 sink，错误只报告一次。

closed 后 `log`/`flush` 返回 `Unavailable`；`withField`/`withRedactor` panic；`isClosed` 为 true。

logger 拥有 sink 的关闭权；不要把同一 sink 交给多个 logger，除非 sink 线程安全且共享语义明确。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AuditLogger(AuditSink sink)` | sink | 非 null | null → panic |

初始状态：`_redactor = null`、`_fields = [:]`、`_closed = false`、`_monitor = new RuntimeMonitor()`。

构造不检查 `sink.isOpen()`；已关闭的 sink 可以注入，但后续写入会返回 `Unavailable`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `log` | 写审计事件 | `AuditEvent event` | `Result<Unit, Error>` | closed → `Unavailable`；sink 错误原样返回；null → panic |
| `logAction` | 便捷写动作 | `String actor, String action, String resource, String outcome` | `Result<Unit, Error>` | 非法字符串 → panic；closed → `Unavailable`；sink 错误 |
| `withField` | 添加默认字段 | `String key, String value` | `AuditLogger`（self） | 非法/closed → panic |
| `withRedactor` | 设置脱敏器 | `Redactor redactor` | `AuditLogger`（self） | null/closed → panic |
| `flush` | 刷新 sink | 无 | `Result<Unit, Error>` | closed → `Unavailable`；sink 错误 |
| `close` | 幂等关闭 | 无 | `Result<Unit, Error>` | flush 错误；第二次 `Ok(unit)` |
| `isClosed` | 是否已关闭 | 无 | `Bool` | 无 |

说明：

- `log` 顺序固定为：默认字段合并 → 脱敏 → `sink.write`；`sink.write` 的结果不包装、不重试。
- `log` 在 sink 失败后保持 open；不自动关闭、不丢弃后续事件。
- `logAction` 用 `AuditEvent.of` 构造 Info 事件（`nowMono()`、空字段），再调用 `log`；需要 Warning/Critical 时用 `AuditEvent.of(...).withLevel(...)` 后 `log`。
- `withField` 替换同名默认字段；返回同一实例，便于链式调用。事件自身的同名字段仍然优先。
- `withRedactor` 替换当前 redactor；旧 redactor 不被修改。用新的空 `Redactor` 关闭脱敏。
- `flush` 只刷新 sink；不改变 closed 状态，不自动 close。
- `close` 先置 closed 再 flush，阻止并发新事件；flush 失败仍调用 `sink.close`，返回 `Err`；第二次 close 不再触碰 sink。
- `isClosed` 是唯一状态查询；不提供 `isOpen`，避免与 sink 的 `isOpen` 混淆。

---

## 8. 使用的技术

- 运行时监视器；
- 可变 builder/链式配置；
- 同步写入管道；
- 默认字段合并；
- 错误原样传播；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、final 字段、Map、Bool、Result、Unit；
- 运行时：`RuntimeMonitor.enter/exit`、`nowMono`；
- 接口：`AuditSink`、`AuditEvent`、`AuditLevel`、`Redactor`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`AuditSink`、`AuditEvent`、`AuditLevel`、`Redactor`、`Error`、`BasicError`、`ErrorKind.Unavailable`、`RuntimeMonitor`、`nowMono`。

---

## 11. 所有权与并发

引用语义；logger 拥有 sink 的关闭权；调用方拥有 logger。

线程安全；所有公开方法在监视器内；`log` 持有监视器跨 `sink.write`，保证事件顺序并与 `close` 互斥。sink 被一个 logger 独占时无需线程安全；共享时由 sink 实现同步。redactor 可共享，logger 只持有引用，不复制规则。

禁止 sink/redactor 回调 logger（`RuntimeMonitor` 不可重入）。无 Context/取消/超时；sink 阻塞会阻塞 `log`/`flush`/`close`；异步 sink 是 X。

---

## 12. 示例与反例

正确：应用实现 sink；`Redactor` 编译并添加规则；`logger.withField("service","billing").withRedactor(redactor)`；`logAction` 记录登录/授权；在检查点 `flush`；退出时 `close`。  
反例：把 `AuditLogger` 当调试 logger；忽略 `log` 返回的 `Err`；期望 `withField` 返回新 logger；期望 close 后写入被静默丢弃；多个 logger 共享非线程安全 sink；期望 `log` 自动 flush；close 两次期望报错。

---

## 13. 测试/场景义务

构造 null；open 时 `log`；closed 时 `log`/`flush`；默认字段合并与事件优先；脱敏顺序；`logAction` 的级别和时间戳；sink 错误原样返回；`flush` open/closed；`close` 幂等与 flush 失败；`withField`/`withRedactor` 变异与链式返回；并发 `log`/`close`；sink.close 只调用一次；`isClosed`；禁止重入。

---

## 14. XNull 伪代码

```xnull
class AuditLogger {
    final AuditSink _sink
    final RuntimeMonitor _monitor
    final Map<String, String> _fields
    Redactor? _redactor
    Bool _closed = false

    AuditLogger(AuditSink sink) {
        if sink == null { throw "AuditLogger: null sink" }
        _sink = sink
        _monitor = new RuntimeMonitor()
        _fields = [:]
        _redactor = null
    }

    Result<Unit, Error> log(AuditEvent event) {
        if event == null { throw "AuditLogger.log: null event" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(self.closedError())
        }
        AuditEvent prepared = self.applyDefaults(event)
        if _redactor != null {
            prepared = _redactor.redactEvent(prepared)
        }
        Result<Unit, Error> result = _sink.write(prepared)
        _monitor.exit()
        return result
    }

    Result<Unit, Error> logAction(String actor, String action,
                                  String resource, String outcome) {
        AuditEvent event = AuditEvent.of(actor, action, resource, outcome)
        return self.log(event)
    }

    AuditLogger withField(String key, String value) {
        if key == null || key == "" { throw "AuditLogger.withField: empty key" }
        if value == null { throw "AuditLogger.withField: null value" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            throw "AuditLogger.withField: closed"
        }
        _fields.put(key, value)
        _monitor.exit()
        return self
    }

    AuditLogger withRedactor(Redactor redactor) {
        if redactor == null { throw "AuditLogger.withRedactor: null redactor" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            throw "AuditLogger.withRedactor: closed"
        }
        _redactor = redactor
        _monitor.exit()
        return self
    }

    Result<Unit, Error> flush() {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(self.closedError())
        }
        Result<Unit, Error> result = _sink.flush()
        _monitor.exit()
        return result
    }

    Result<Unit, Error> close() {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Ok(unit)
        }
        _closed = true
        Result<Unit, Error> flushed = _sink.flush()
        _sink.close()
        _monitor.exit()
        if flushed.isErr() {
            return Err(flushed.error())
        }
        return Ok(unit)
    }

    Bool isClosed() {
        _monitor.enter()
        Bool result = _closed
        _monitor.exit()
        return result
    }

    private AuditEvent applyDefaults(AuditEvent event) {
        AuditEvent result = event
        Map<String, String> existing = event.fields()
        List<String> keys = _fields.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if !existing.has(key) {
                result = result.withField(key, _fields.getOr(key, ""))
            }
            index = index + 1
        }
        return result
    }

    private Error closedError() {
        return new BasicError(ErrorKind.Unavailable, "audit logger is closed")
    }
}
```
