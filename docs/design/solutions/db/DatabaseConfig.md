# `DatabaseConfig`

| 项 | 值 |
| --- | --- |
| 类型 | `class DatabaseConfig` |
| 包 | `xdk.db` |
| 稳定性 | `preview` |
| 依赖 | `IsolationLevel`、`SqlStatement`、`Map`、`Error` |
| 被依赖 | [`DatabasePool`](DatabasePool.md)、[`Db`](Db.md) |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

数据库句柄/连接池的不可变配置：逻辑名、连接 URI、驱动 open options、池大小、获取/空闲/生命周期/校验超时、隔离级别、预热与获取时校验策略、可选校验语句。

不做：解析连接 URI、管理凭据、驱动注册、SQL 生成、每事务隔离级别、池运行状态、重连策略、日志输出。

---

## 2. 设计逻辑

- 配置是**不可变值**：构造后只读；所有 `with*` 返回新对象；`Map` 在构造时复制、读取时返回副本。
- 配置可能含口令/令牌，因此：
  - 不提供 `equals`/哈希，避免把秘密放进通用比较/容器；
  - `describe` 不输出 URI、open option 键值、校验语句正文；
  - 只有 `connectionUri()`/`openOptions()` 供池实现读取，调用方不得记录返回值。
- 池参数采用主流池的最小集：
  - `minimumIdle`/`maximumPoolSize`：空闲下限与总量上限；
  - `acquireTimeoutMillis`：等待连接的上限；`0` 表示只受 `Context` 约束；
  - `idleTimeoutMillis`：空闲连接回收；`0` 表示不按空闲时间回收；
  - `maximumLifetimeMillis`：连接最大复用寿命；`0` 表示不按寿命回收；
  - `validationTimeoutMillis`：获取时校验的单次上限；`0` 表示不单独限时；
  - `leakDetectionThresholdMillis`：租约持有过久的诊断阈值；`0` 表示关闭；
  - `failFast`：打开池时是否立即建立并验证初始连接；
  - `validateOnAcquire`：每次借出前是否校验；有 `validationStatement` 时执行语句，否则只检查 `isOpen`。
- 默认值面向常见服务端：`maximumPoolSize=10`、`minimumIdle=0`、获取 30s、空闲 10min、寿命 30min、校验 5s、`failFast=true`、`validateOnAcquire=true`、不启用泄漏检测。
- 连接 URI 对 `xdk.db` 不透明：只要求非空；scheme、参数、TLS、认证由驱动解析。`xdk.db` 不拆分、不改写、不拼接。
- 驱动不在配置中重复：`SqlDriver` 由 `Db.open`/`DatabasePool.open` 显式传入；`DatabaseConfig` 只承载该驱动的 open options，避免“配置里的驱动名”和“实际注入的驱动”冲突。
- `openOptions` 是驱动专有键值；未知键由驱动返回 `InvalidArgument`。保留键 `xdk.isolationLevel` 不允许调用方直接设置，必须通过 `isolationLevel` 字段，避免与池的隔离级别设置冲突。
- 隔离级别是池级：所有连接以同一级别打开；v1 不支持每事务覆盖。驱动不支持时 `DatabasePool.open` 返回 `Unsupported`，不得静默降级。
- 校验语句是可选 `SqlStatement`；池在获取连接时执行它（通常 `select 1` 或方言等价语句），忽略结果，只关心成功/失败。语句由调用方按方言提供；`xdk.db` 不生成。
- 配置非法是调用方合同错误（panic），不是 `Result`：这些错误应在进程启动时暴露，而不是在每次取连接时重复。
- 无 close；不可变；可跨任务共享；连接池在 `open` 开始时复制所需值，之后替换配置不影响已打开的池。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 池/数据库逻辑名；1..64，字母开头，仅字母/数字/`_`/`-` |
| `_connectionUri` | `String` | final | 非空；对核心不透明；敏感 |
| `_openOptions` | `Map<String,String>` | final | 构造时复制；键非空、无空白/控制字符；保留键禁止 |
| `_isolationLevel` | `IsolationLevel?` | final | null = 驱动默认；非 null = 池级要求 |
| `_minimumIdle` | `Int` | final | `0..maximumPoolSize` |
| `_maximumPoolSize` | `Int` | final | `≥1` |
| `_acquireTimeoutMillis` | `Long` | final | `≥0`；0 = 只受 Context 约束 |
| `_idleTimeoutMillis` | `Long` | final | `≥0`；0 = 不按空闲时间回收 |
| `_maximumLifetimeMillis` | `Long` | final | `≥0`；0 = 不按寿命回收 |
| `_validationTimeoutMillis` | `Long` | final | `≥0`；0 = 不单独限时；非 0 时须小于获取超时（获取超时非 0） |
| `_leakDetectionThresholdMillis` | `Long` | final | 0 或 `≥1000` |
| `_failFast` | `Bool` | final | 打开池时是否立即验证连接 |
| `_validateOnAcquire` | `Bool` | final | 借出前是否校验 |
| `_validationStatement` | `SqlStatement?` | final | 可选；非 null 时用于获取校验 |

不变量：

- 名称、URI 非 null；名称格式合法；URI trim 后非空。
- `_openOptions` 非 null；无 null 键/值；键格式合法；不含保留键。
- `0 ≤ minimumIdle ≤ maximumPoolSize`；`maximumPoolSize ≥ 1`。
- 六个时间为 `Long` 毫秒且 `≥0`；泄漏阈值为 0 或 `≥1000`。
- 获取超时与校验超时同时非 0 时，校验超时严格小于获取超时。
- 对象不可变；`openOptions()` 返回独立副本。
- `validationStatement` 非 null 时只读；构造后不可替换。

---

## 4. 生命周期

由构造器/`DatabaseConfig.of` 创建；构造后不可变；无 close；GC 管理内存；可跨任务共享。

- 每个 `with*` 返回新配置；原配置不受影响。
- `DatabasePool.open` 在开始时读取配置并复制所需值；之后修改/丢弃原配置不影响池。
- 配置对象可由多个池共享；池不修改它。
- 不含运行时资源；持有可能敏感的字符串/映射，生命周期由调用方控制。

---

## 5. 构造契约

| 构造/工厂 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DatabaseConfig(String name, String connectionUri, Map<String,String> openOptions, IsolationLevel? isolationLevel, Int minimumIdle, Int maximumPoolSize, Long acquireTimeoutMillis, Long idleTimeoutMillis, Long maximumLifetimeMillis, Long validationTimeoutMillis, Long leakDetectionThresholdMillis, Bool failFast, Bool validateOnAcquire, SqlStatement? validationStatement)` | 14 个字段 | 见 §3 | 非法 → panic |
| `DatabaseConfig.of(String name, String connectionUri)` | name/URI | 同上；其余用默认值 | 非法 → panic |

`DatabaseConfig.of` 的默认值：

| 字段 | 默认 |
| --- | --- |
| `openOptions` | 空映射 |
| `isolationLevel` | null（驱动默认） |
| `minimumIdle` | 0 |
| `maximumPoolSize` | 10 |
| `acquireTimeoutMillis` | 30000 |
| `idleTimeoutMillis` | 600000 |
| `maximumLifetimeMillis` | 1800000 |
| `validationTimeoutMillis` | 5000 |
| `leakDetectionThresholdMillis` | 0（关闭） |
| `failFast` | true |
| `validateOnAcquire` | true |
| `validationStatement` | null |

构造复制 `openOptions`；调用方之后修改原映射不影响配置。非法名称、空 URI、负值、`minimumIdle > maximumPoolSize`、保留键、非法键值、非法超时关系均 panic，并给出字段名。

---

## 6. 字段表

见 §3；字段私有。

`_connectionUri` 与 `_openOptions` 是敏感字段：实现不得在 `describe`、错误、日志中输出其内容。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `of` | 最小配置 | `String name, String connectionUri` | `DatabaseConfig` | 非法 → panic | 默认值见 §5 |
| `name` | 逻辑名 | 无 | `String` | 无 | 非敏感 |
| `connectionUri` | 连接 URI | 无 | `String` | 无 | 敏感；不得记录 |
| `openOptions` | 驱动选项快照 | 无 | `Map<String,String>` | 无 | 副本；敏感 |
| `isolationLevel` | 隔离级别 | 无 | `IsolationLevel?` | 无 | null = 驱动默认 |
| `minimumIdle` | 空闲下限 | 无 | `Int` | 无 | `0..maximumPoolSize` |
| `maximumPoolSize` | 总量上限 | 无 | `Int` | 无 | `≥1` |
| `acquireTimeoutMillis` | 获取超时 | 无 | `Long` | 无 | 0 = 只受 Context 约束 |
| `idleTimeoutMillis` | 空闲回收 | 无 | `Long` | 无 | 0 = 不回收 |
| `maximumLifetimeMillis` | 最大寿命 | 无 | `Long` | 无 | 0 = 不限 |
| `validationTimeoutMillis` | 校验超时 | 无 | `Long` | 无 | 0 = 不单独限时 |
| `leakDetectionThresholdMillis` | 泄漏阈值 | 无 | `Long` | 无 | 0 = 关闭 |
| `failFast` | 打开即验证 | 无 | `Bool` | 无 | 默认 true |
| `validateOnAcquire` | 借出前校验 | 无 | `Bool` | 无 | 默认 true |
| `validationStatement` | 校验语句 | 无 | `SqlStatement?` | 无 | 可为 null |
| `withOpenOptions` | 替换驱动选项 | `Map<String,String> options` | `DatabaseConfig` | null/非法 → panic | 复制；新对象 |
| `withOpenOption` | 增加/替换选项 | `String key, String value` | `DatabaseConfig` | null/非法/保留键 → panic | 新对象 |
| `withIsolationLevel` | 设置隔离级别 | `IsolationLevel? level` | `DatabaseConfig` | 无 | null 清除 |
| `withPoolSize` | 设置池大小 | `Int minimumIdle, Int maximumPoolSize` | `DatabaseConfig` | 非法 → panic | 交叉校验 |
| `withAcquireTimeoutMillis` | 设置获取超时 | `Long value` | `DatabaseConfig` | 负值 → panic | 与校验超时交叉校验 |
| `withIdleTimeoutMillis` | 设置空闲回收 | `Long value` | `DatabaseConfig` | 负值 → panic | 0 = 不回收 |
| `withMaximumLifetimeMillis` | 设置最大寿命 | `Long value` | `DatabaseConfig` | 负值 → panic | 0 = 不限 |
| `withValidationTimeoutMillis` | 设置校验超时 | `Long value` | `DatabaseConfig` | 负值/与获取超时冲突 → panic | 0 = 不单独限时 |
| `withLeakDetectionThresholdMillis` | 设置泄漏阈值 | `Long value` | `DatabaseConfig` | 非 0 且 <1000 → panic | 0 = 关闭 |
| `withFailFast` | 设置打开即验证 | `Bool value` | `DatabaseConfig` | 无 | 新对象 |
| `withValidateOnAcquire` | 设置借出前校验 | `Bool value` | `DatabaseConfig` | 无 | 新对象 |
| `withValidationStatement` | 设置校验语句 | `SqlStatement? statement` | `DatabaseConfig` | 无 | null 清除 |
| `copy` | 独立副本 | 无 | `DatabaseConfig` | 无 | 映射再复制 |
| `describe` | 单行诊断 | 无 | `String` | 无 | 不含 URI/选项值/SQL |

详细契约：

- 所有 `with*` 至少改变一个字段，返回新对象；未改变字段沿用当前值；`Map` 重新复制。
- `withOpenOptions` 替换整个映射；要逐项增加用 `withOpenOption`。
- `withOpenOption` 的 key 为空白/null、value 为 null、key 为保留键 `xdk.isolationLevel` 时 panic；同名键替换旧值。
- `withIsolationLevel(null)` 清除隔离级别；非 null 时不做驱动能力检查，能力在 `DatabasePool.open` 时验证。
- `withPoolSize` 同时校验 `minimumIdle <= maximumPoolSize`；只改一个值用两次调用不推荐，应一次传入两个值。
- `withAcquireTimeoutMillis(0)` 表示等待只受 `Context` 控制；`withValidationTimeoutMillis(0)` 表示校验不单独限时。
- `withLeakDetectionThresholdMillis` 只接受 0 或 `≥1000`；1..999 是合同错误。
- `withValidationStatement` 不要求语句是查询；执行成功即视为连接可用；语句参数值由调用方负责，不得含秘密。
- `connectionUri()` 返回不可变 String；`openOptions()` 返回独立 `Map`，调用方修改副本不影响配置。
- `describe` 形如 `"DatabaseConfig(name=orders pool=10 idle=0 acquireMs=30000 idleMs=600000 lifeMs=1800000 isolation=driver-default failFast=true validate=true options=2 uri=<redacted>)"`；不输出任何 option 键值或 SQL。
- 不提供 `equals`/哈希：配置含秘密，按引用身份比较；需要比较时逐字段读取并由调用方决定是否比较敏感字段。
- 不提供 `toString` 之外的序列化；配置持久化由应用负责。

---

## 8. 使用的技术

- 不可变配置对象；
- 防御性复制映射；
- 字段交叉校验；
- 零值语义（0 = 关闭/不限/默认）；
- 敏感字段脱敏；
- 保留键隔离；
- 链式派生（`with*`）。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Int、Long、Bool、Map、nullable 类型；
- 运行时：`trim(String)`、`substring(Int,Int)`、`str(Int)`、`str(Long)`、`Map.copy`/键遍历、`isAsciiLetter`/`isAsciiDigit`；
- 接口：`IsolationLevel`、`isolationLevelName`、`SqlStatement`、`Error`、`BasicError`。

---

## 10. 依赖的特性/接口/类

[`IsolationLevel`](IsolationLevel.md)、[`isolationLevelName`](IsolationLevel.md)、[`SqlStatement`](../../network/sql/SqlStatement.md)、[`DatabasePool`](DatabasePool.md)、[`Db`](Db.md)。被 `DatabasePool.open` 读取；不依赖驱动类型。

---

## 11. 所有权与并发

- 不可变；可跨任务共享；无资源；无取消点。
- 构造复制 `openOptions`；`openOptions()` 再复制，调用方无法通过返回值修改内部映射。
- `SqlStatement` 不可变；配置只持有引用，不复制语句。
- 相等：引用身份；不提供 `equals`/哈希；不推荐作 `Map` 键。
- 排序：不提供。
- 敏感数据生命周期由调用方控制；配置对象被丢弃后由 GC 回收，本包不落盘、不日志。

---

## 12. 示例与反例

正确：

```text
DatabaseConfig config = DatabaseConfig
    .of("orders", "postgres://db.example/app")
    .withOpenOption("sslmode", "require")
    .withPoolSize(2, 20)
    .withAcquireTimeoutMillis(5000)
    .withIsolationLevel(IsolationLevel.ReadCommitted)
    .withValidationStatement(new SqlStatement("select 1"))
```

```text
Db.open(context, driver, config)
```

反例：

- 把完整 URI 放进日志或错误消息；`describe` 只显示 `<redacted>`。
- 直接设置 `xdk.isolationLevel` open option，与 `isolationLevel` 字段冲突。
- `minimumIdle=50`、`maximumPoolSize=10`；构造 panic。
- `validationTimeoutMillis >= acquireTimeoutMillis` 且两者非 0；构造 panic。
- 每次请求都新建配置/池；池应长生命周期，配置应启动时构造一次。
- 期望 `with*` 修改原对象；它返回新对象。
- 把 `validationStatement` 写成含秘密参数的 DML；校验语句应无参数、无副作用。
- 把 `null` 隔离级别解释为 `ReadCommitted`；它是驱动默认。
- 依赖 `connectionUri()` 的字符串格式做业务判断；URI 对 `xdk.db` 不透明。

---

## 13. 测试/场景义务

- 默认值完整性；最小工厂与全参构造一致；
- 名称合法/非法（空、空白、数字开头、超长、非法字符）；
- URI null/空/空白 panic；
- openOptions null、null 键/值、空键、非法字符、保留键 panic；
- openOptions 构造复制；`openOptions()` 副本独立；`withOpenOption` 替换/新增；
- 池大小边界：0/1/max、min > max、负值；
- 六个时间边界：0、1、负值、超大 Long；校验超时与获取超时冲突；
- 泄漏阈值 0/999/1000/负值；
- 隔离级别 null/四个成员；`withIsolationLevel(null)` 清除；
- 每个 `with*` 返回新对象且其余字段不变；
- `copy` 独立；
- `describe` 不含 URI、option 键值、SQL 正文；
- 配置跨任务只读共享；池打开后修改原配置不影响池。

---

## 14. XNull 伪代码

```xnull
class DatabaseConfig {
    final String _name
    final String _connectionUri
    final Map<String, String> _openOptions
    final IsolationLevel? _isolationLevel
    final Int _minimumIdle
    final Int _maximumPoolSize
    final Long _acquireTimeoutMillis
    final Long _idleTimeoutMillis
    final Long _maximumLifetimeMillis
    final Long _validationTimeoutMillis
    final Long _leakDetectionThresholdMillis
    final Bool _failFast
    final Bool _validateOnAcquire
    final SqlStatement? _validationStatement

    DatabaseConfig(String name, String connectionUri,
                   Map<String, String> openOptions,
                   IsolationLevel? isolationLevel,
                   Int minimumIdle, Int maximumPoolSize,
                   Long acquireTimeoutMillis, Long idleTimeoutMillis,
                   Long maximumLifetimeMillis, Long validationTimeoutMillis,
                   Long leakDetectionThresholdMillis,
                   Bool failFast, Bool validateOnAcquire,
                   SqlStatement? validationStatement) {
        if name == null || trim(name) == "" {
            throw "DatabaseConfig: empty name"
        }
        if name.length() > 64 {
            throw "DatabaseConfig: name too long"
        }
        if !isValidPoolName(name) {
            throw "DatabaseConfig: invalid name"
        }
        if connectionUri == null || trim(connectionUri) == "" {
            throw "DatabaseConfig: empty connectionUri"
        }
        if openOptions == null {
            throw "DatabaseConfig: null openOptions"
        }
        if maximumPoolSize < 1 {
            throw "DatabaseConfig: maximumPoolSize < 1"
        }
        if minimumIdle < 0 || minimumIdle > maximumPoolSize {
            throw "DatabaseConfig: invalid minimumIdle"
        }
        if acquireTimeoutMillis < 0 || idleTimeoutMillis < 0
                || maximumLifetimeMillis < 0 || validationTimeoutMillis < 0 {
            throw "DatabaseConfig: negative timeout"
        }
        if acquireTimeoutMillis > 0 && validationTimeoutMillis > 0
                && validationTimeoutMillis >= acquireTimeoutMillis {
            throw "DatabaseConfig: validationTimeout must be less than acquireTimeout"
        }
        if leakDetectionThresholdMillis < 0 {
            throw "DatabaseConfig: negative leak threshold"
        }
        if leakDetectionThresholdMillis > 0
                && leakDetectionThresholdMillis < 1000 {
            throw "DatabaseConfig: leak threshold below 1000"
        }
        Map<String, String> optionCopy = [:]
        List<String> optionKeys = openOptions.keys()
        Int optionIndex = 0
        while optionIndex < optionKeys.length() {
            String key = optionKeys.get(optionIndex)
            String value = openOptions.getOr(key, "")
            if key == null || key == "" || !isValidOptionKey(key) {
                throw "DatabaseConfig: invalid option key"
            }
            if key == "xdk.isolationLevel" {
                throw "DatabaseConfig: reserved isolation option"
            }
            if value == null || !isValidOptionValue(value) {
                throw "DatabaseConfig: invalid option value"
            }
            optionCopy.put(key, value)
            optionIndex = optionIndex + 1
        }
        _name = name
        _connectionUri = connectionUri
        _openOptions = optionCopy
        _isolationLevel = isolationLevel
        _minimumIdle = minimumIdle
        _maximumPoolSize = maximumPoolSize
        _acquireTimeoutMillis = acquireTimeoutMillis
        _idleTimeoutMillis = idleTimeoutMillis
        _maximumLifetimeMillis = maximumLifetimeMillis
        _validationTimeoutMillis = validationTimeoutMillis
        _leakDetectionThresholdMillis = leakDetectionThresholdMillis
        _failFast = failFast
        _validateOnAcquire = validateOnAcquire
        _validationStatement = validationStatement
    }

    static DatabaseConfig of(String name, String connectionUri) {
        return new DatabaseConfig(name, connectionUri, [:], null, 0, 10,
            30000, 600000, 1800000, 5000, 0, true, true, null)
    }

    String name() { return _name }
    String connectionUri() { return _connectionUri }

    Map<String, String> openOptions() {
        Map<String, String> result = [:]
        List<String> keys = _openOptions.keys()
        Int index = 0
        while index < keys.length() {
            result.put(keys.get(index), _openOptions.getOr(keys.get(index), ""))
            index = index + 1
        }
        return result
    }

    IsolationLevel? isolationLevel() { return _isolationLevel }
    Int minimumIdle() { return _minimumIdle }
    Int maximumPoolSize() { return _maximumPoolSize }
    Long acquireTimeoutMillis() { return _acquireTimeoutMillis }
    Long idleTimeoutMillis() { return _idleTimeoutMillis }
    Long maximumLifetimeMillis() { return _maximumLifetimeMillis }
    Long validationTimeoutMillis() { return _validationTimeoutMillis }
    Long leakDetectionThresholdMillis() { return _leakDetectionThresholdMillis }
    Bool failFast() { return _failFast }
    Bool validateOnAcquire() { return _validateOnAcquire }
    SqlStatement? validationStatement() { return _validationStatement }

    DatabaseConfig withOpenOptions(Map<String, String> options) {
        return new DatabaseConfig(_name, _connectionUri, options,
            _isolationLevel, _minimumIdle, _maximumPoolSize,
            _acquireTimeoutMillis, _idleTimeoutMillis,
            _maximumLifetimeMillis, _validationTimeoutMillis,
            _leakDetectionThresholdMillis, _failFast,
            _validateOnAcquire, _validationStatement)
    }

    DatabaseConfig withOpenOption(String key, String value) {
        if key == null || value == null {
            throw "DatabaseConfig.withOpenOption: null"
        }
        Map<String, String> next = _openOptions.copy()
        next.put(key, value)
        return new DatabaseConfig(_name, _connectionUri, next,
            _isolationLevel, _minimumIdle, _maximumPoolSize,
            _acquireTimeoutMillis, _idleTimeoutMillis,
            _maximumLifetimeMillis, _validationTimeoutMillis,
            _leakDetectionThresholdMillis, _failFast,
            _validateOnAcquire, _validationStatement)
    }

    DatabaseConfig withIsolationLevel(IsolationLevel? level) {
        return new DatabaseConfig(_name, _connectionUri, _openOptions,
            level, _minimumIdle, _maximumPoolSize,
            _acquireTimeoutMillis, _idleTimeoutMillis,
            _maximumLifetimeMillis, _validationTimeoutMillis,
            _leakDetectionThresholdMillis, _failFast,
            _validateOnAcquire, _validationStatement)
    }

    DatabaseConfig withPoolSize(Int minimumIdle, Int maximumPoolSize) {
        return new DatabaseConfig(_name, _connectionUri, _openOptions,
            _isolationLevel, minimumIdle, maximumPoolSize,
            _acquireTimeoutMillis, _idleTimeoutMillis,
            _maximumLifetimeMillis, _validationTimeoutMillis,
            _leakDetectionThresholdMillis, _failFast,
            _validateOnAcquire, _validationStatement)
    }

    DatabaseConfig withAcquireTimeoutMillis(Long value) {
        return new DatabaseConfig(_name, _connectionUri, _openOptions,
            _isolationLevel, _minimumIdle, _maximumPoolSize,
            value, _idleTimeoutMillis, _maximumLifetimeMillis,
            _validationTimeoutMillis, _leakDetectionThresholdMillis,
            _failFast, _validateOnAcquire, _validationStatement)
    }

    DatabaseConfig withIdleTimeoutMillis(Long value) {
        return new DatabaseConfig(_name, _connectionUri, _openOptions,
            _isolationLevel, _minimumIdle, _maximumPoolSize,
            _acquireTimeoutMillis, value, _maximumLifetimeMillis,
            _validationTimeoutMillis, _leakDetectionThresholdMillis,
            _failFast, _validateOnAcquire, _validationStatement)
    }

    DatabaseConfig withMaximumLifetimeMillis(Long value) {
        return new DatabaseConfig(_name, _connectionUri, _openOptions,
            _isolationLevel, _minimumIdle, _maximumPoolSize,
            _acquireTimeoutMillis, _idleTimeoutMillis, value,
            _validationTimeoutMillis, _leakDetectionThresholdMillis,
            _failFast, _validateOnAcquire, _validationStatement)
    }

    DatabaseConfig withValidationTimeoutMillis(Long value) {
        return new DatabaseConfig(_name, _connectionUri, _openOptions,
            _isolationLevel, _minimumIdle, _maximumPoolSize,
            _acquireTimeoutMillis, _idleTimeoutMillis,
            _maximumLifetimeMillis, value, _leakDetectionThresholdMillis,
            _failFast, _validateOnAcquire, _validationStatement)
    }

    DatabaseConfig withLeakDetectionThresholdMillis(Long value) {
        return new DatabaseConfig(_name, _connectionUri, _openOptions,
            _isolationLevel, _minimumIdle, _maximumPoolSize,
            _acquireTimeoutMillis, _idleTimeoutMillis,
            _maximumLifetimeMillis, _validationTimeoutMillis, value,
            _failFast, _validateOnAcquire, _validationStatement)
    }

    DatabaseConfig withFailFast(Bool value) {
        return new DatabaseConfig(_name, _connectionUri, _openOptions,
            _isolationLevel, _minimumIdle, _maximumPoolSize,
            _acquireTimeoutMillis, _idleTimeoutMillis,
            _maximumLifetimeMillis, _validationTimeoutMillis,
            _leakDetectionThresholdMillis, value,
            _validateOnAcquire, _validationStatement)
    }

    DatabaseConfig withValidateOnAcquire(Bool value) {
        return new DatabaseConfig(_name, _connectionUri, _openOptions,
            _isolationLevel, _minimumIdle, _maximumPoolSize,
            _acquireTimeoutMillis, _idleTimeoutMillis,
            _maximumLifetimeMillis, _validationTimeoutMillis,
            _leakDetectionThresholdMillis, _failFast,
            value, _validationStatement)
    }

    DatabaseConfig withValidationStatement(SqlStatement? statement) {
        return new DatabaseConfig(_name, _connectionUri, _openOptions,
            _isolationLevel, _minimumIdle, _maximumPoolSize,
            _acquireTimeoutMillis, _idleTimeoutMillis,
            _maximumLifetimeMillis, _validationTimeoutMillis,
            _leakDetectionThresholdMillis, _failFast,
            _validateOnAcquire, statement)
    }

    DatabaseConfig copy() {
        return new DatabaseConfig(_name, _connectionUri, _openOptions,
            _isolationLevel, _minimumIdle, _maximumPoolSize,
            _acquireTimeoutMillis, _idleTimeoutMillis,
            _maximumLifetimeMillis, _validationTimeoutMillis,
            _leakDetectionThresholdMillis, _failFast,
            _validateOnAcquire, _validationStatement)
    }

    String describe() {
        String isolation = "driver-default"
        if _isolationLevel != null {
            IsolationLevel level = _isolationLevel as IsolationLevel
            isolation = isolationLevelName(level)
        }
        String validation = "isOpen"
        if _validationStatement != null {
            validation = "statement"
        }
        return "DatabaseConfig(name=" + _name
            + " pool=" + str(_maximumPoolSize)
            + " idle=" + str(_minimumIdle)
            + " acquireMs=" + str(_acquireTimeoutMillis)
            + " idleMs=" + str(_idleTimeoutMillis)
            + " lifeMs=" + str(_maximumLifetimeMillis)
            + " isolation=" + isolation
            + " failFast=" + str(_failFast)
            + " validate=" + str(_validateOnAcquire)
            + " validation=" + validation
            + " options=" + str(_openOptions.length())
            + " uri=<redacted>)"
    }

    private static Bool isValidPoolName(String name) {
        if name == null || name.length() == 0 || name.length() > 64 {
            return false
        }
        String first = name.substring(0, 1)
        if !isAsciiLetter(first) {
            return false
        }
        Int index = 0
        while index < name.length() {
            String character = name.substring(index, 1)
            if !isAsciiLetter(character) && !isAsciiDigit(character)
                    && character != "_" && character != "-" {
                return false
            }
            index = index + 1
        }
        return true
    }

    private static Bool isValidOptionKey(String key) {
        if key == null || key.length() == 0 || key.length() > 128 {
            return false
        }
        Int index = 0
        while index < key.length() {
            String character = key.substring(index, 1)
            if character == " " || character == "\t" || character == "\n"
                    || character == "\r" {
                return false
            }
            index = index + 1
        }
        return true
    }

    private static Bool isValidOptionValue(String value) {
        if value == null || value.length() > 4096 {
            return false
        }
        Int index = 0
        while index < value.length() {
            String character = value.substring(index, 1)
            if character == "\n" || character == "\r" || character == "\t" {
                return false
            }
            index = index + 1
        }
        return true
    }
}
```

> 伪代码非可执行。`isValidPoolName`/`isValidOptionKey`/`isValidOptionValue` 是类内私有静态辅助，不属于包 API；`isAsciiLetter`/`isAsciiDigit` 是文本运行时原语；`Map.copy` 与键遍历复制映射。保留键字面量 `xdk.isolationLevel` 与 [`Db.isolationOpenOptionKey`](Db.md) 必须一致。
