# `SessionOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class SessionOptions` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `ExecutionProvider`、`Map`、`Long` |

---

## 1. 定位

推理会话的显式配置：执行提供者优先级、线程数、图优化/内存模式/性能分析开关、确定性、CPU 回退、内存上限和提供者选项。

只描述“如何创建会话”，不创建会话、不读取全局配置、不探测设备、不选择最优提供者。

不做：设备枚举、驱动配置、算子分区、内核调优、自动混合精度、量化、缓存目录、远程配置。

---

## 2. 设计逻辑

- 用 `class`：需要复制提供者列表和选项映射，并对线程数/上限/重复提供者做合同校验。
- 不可变：构造后只读；所有 `with` 式修改都不提供，需要变更时重新构造。
- 提供者顺序是优先级：列表第一个优先级最高；CPU 回退是独立布尔开关，不用“列表里有没有 CPU”猜。
- 线程数 `0` 表示运行时默认；负数非法。内部/外部线程数分开，避免把两种并行度混成一个值。
- 内存上限 `0` 表示不设显式上限；非零是字节数，`Long` 表达，适配器可拒绝超过运行时能力的值。
- 提供者选项是 `Map<String,String>` 快照：键采用 `provider.option` 形式，适配器解释；本类只校验非空/无空白，不猜测语义。
- `defaults()` 是唯一预设：CPU、运行时默认线程、开启图优化/内存模式、关闭性能分析/确定性、开启 CPU 回退、无显式内存上限、空选项。
- 不提供全局默认对象；每次 `defaults()` 返回新实例。
- 不包含 `Context`：构造配置不阻塞；打开会话时由 `Ml.openSession` 接收 `Context`。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_providers` | `List<ExecutionProvider>` | final | 非空；元素非 null；无重复；副本；顺序即优先级 |
| `_intraOpThreadCount` | `Int` | final | ≥0；0 = 运行时默认 |
| `_interOpThreadCount` | `Int` | final | ≥0；0 = 运行时默认 |
| `_enableGraphOptimization` | `Bool` | final | 是否允许图优化 |
| `_enableMemoryPattern` | `Bool` | final | 是否允许内存模式复用 |
| `_enableProfiling` | `Bool` | final | 是否启用适配器性能分析 |
| `_deterministicCompute` | `Bool` | final | 是否要求确定性计算 |
| `_enableCpuFallback` | `Bool` | final | 未覆盖算子是否允许回退 CPU |
| `_maximumMemoryBytes` | `Long` | final | ≥0；0 = 不设显式上限 |
| `_providerOptions` | `Map<String,String>` | final | 私有快照；键非空、无首尾空白；值非 null |

不变量：提供者列表非空、无重复；线程数/上限非负；所有字段非 null（布尔/数值为值类型）；映射键值合法；构造后不可变；列表/映射返回副本。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可跨任务共享；可被多个 `InferenceSession` 共享。

`defaults()` 每次返回独立对象；修改返回值不可能（无修改器），但调用方可把它传给多个会话。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SessionOptions(List<ExecutionProvider> providers, Int intraOpThreadCount, Int interOpThreadCount, Bool enableGraphOptimization, Bool enableMemoryPattern, Bool enableProfiling, Bool deterministicCompute, Bool enableCpuFallback, Long maximumMemoryBytes, Map<String,String> providerOptions)` | 全部字段 | providers 非空、元素非 null、无重复；线程数 ≥0；上限 ≥0；映射键非空/无首尾空白、值非 null | 违约 → panic |
| `defaults()` | 无 | 固定预设 | 无 |

构造器复制列表与映射；调用方之后修改原容器不影响选项。

---

## 6. 字段表

见 §3；字段私有。不暴露运行时配置对象、设备句柄或线程池。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `providers` | 提供者优先级副本 | 无 | `List<ExecutionProvider>` | 无 | 顺序即优先级 |
| `intraOpThreadCount` | 算子内线程数 | 无 | `Int` | 无 | 0 = 默认 |
| `interOpThreadCount` | 算子间线程数 | 无 | `Int` | 无 | 0 = 默认 |
| `enableGraphOptimization` | 图优化开关 | 无 | `Bool` | 无 | 适配器可忽略 |
| `enableMemoryPattern` | 内存模式开关 | 无 | `Bool` | 无 | 适配器可忽略 |
| `enableProfiling` | 性能分析开关 | 无 | `Bool` | 无 | 适配器可忽略 |
| `deterministicCompute` | 确定性开关 | 无 | `Bool` | 无 | 不保证所有后端支持 |
| `enableCpuFallback` | CPU 回退开关 | 无 | `Bool` | 无 | 显式控制隐式回退 |
| `maximumMemoryBytes` | 内存上限 | 无 | `Long` | 无 | 0 = 不设显式上限 |
| `providerOptions` | 提供者选项副本 | 无 | `Map<String,String>` | 无 | O(n) 复制 |
| `providerOption` | 按 key 读选项 | `String key` | `String?` | null key → panic | 缺失 → null |
| `copy` | 复制 | 无 | `SessionOptions` | 无 | 独立列表/映射 |
| `describe` | 单行描述 | 无 | `String` | 无 | 不输出选项值 |
| `defaults` | 默认配置 | 无 | `SessionOptions` | 无 | 静态工厂 |

说明：

- `providers` 返回副本；修改不影响会话选项。
- `enableGraphOptimization`/`enableMemoryPattern`/`enableProfiling`/`deterministicCompute` 是请求，不是保证；适配器不支持时可忽略或以 `Unsupported` 拒绝整个会话。
- `enableCpuFallback == false` 时，适配器不得隐式追加 CPU；`true` 时允许把 CPU 作为最后回退，即使 `providers` 未列出 CPU。
- `providerOptions` 的键约定为 `"<provider>.<option>"`，例如 `"cuda.device_id"`；键必须非空、无首尾空白；值可为空串，但不能为 null。适配器对未知键可忽略或返回 `Unsupported`。
- `providerOption` 空 key 返回 `null`；不做大小写折叠。
- `copy` 等同于用当前字段重新构造；`defaults` 每次返回新实例。
- 不提供 `withProvider`/`setThreadCount` 等修改器；配置不原地变化。

---

## 8. 使用的技术

- 不可变配置对象；
- 有序提供者列表；
- 列表/映射复制；
- 重复提供者检测；
- 显式布尔开关；
- `Long` 字节上限；
- 静态默认工厂。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Map、Int、Long、Bool、String；
- 运行时：列表/映射复制、字符串去空白；
- 接口：[`ExecutionProvider`](ExecutionProvider.md)、[`InferenceSession`](InferenceSession.md)、[`Ml`](Ml.md)。

---

## 10. 依赖的特性/接口/类

[`ExecutionProvider`](ExecutionProvider.md)、[`InferenceSession`](InferenceSession.md)、[`Ml`](Ml.md)。

不依赖运行时配置对象、环境变量、设备枚举或厂商 SDK。

---

## 11. 所有权与并发

不可变；可共享；列表/映射返回副本；无资源；无取消点。  
相等：没有 `equals`；`==` 是引用身份；需要比较时逐字段比较；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`SessionOptions.defaults()` 做 CPU 基线；`new SessionOptions([ExecutionProvider.Cuda, ExecutionProvider.Cpu], 4, 1, true, true, false, false, true, 0, ["cuda.device_id":"0"])` 显式指定优先级和设备；`enableCpuFallback == false` 时接受未覆盖算子失败。  
反例：用 `providers` 为空表示“自动选择”；在线程数传 `-1` 期望运行时猜默认；把 `maximumMemoryBytes == 0` 当“禁止分配”；在 `enableProfiling` 打开时假设零开销；把提供者选项当全局环境变量；修改 `providers()` 返回值并期望会话变化。

---

## 13. 测试/场景义务

providers 空/重复/null；线程数 0/正/负；上限 0/正/负；四个布尔开关组合；CPU 回退开/关；providerOptions 空/非空/键空白/值 null；`providerOption` 命中/缺失/null/空；`copy` 独立；`defaults` 每次新实例；`describe` 不泄露选项值；多会话共享同一选项。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class SessionOptions {
    final List<ExecutionProvider> _providers
    final Int _intraOpThreadCount
    final Int _interOpThreadCount
    final Bool _enableGraphOptimization
    final Bool _enableMemoryPattern
    final Bool _enableProfiling
    final Bool _deterministicCompute
    final Bool _enableCpuFallback
    final Long _maximumMemoryBytes
    final Map<String, String> _providerOptions

    SessionOptions(List<ExecutionProvider> providers, Int intraOpThreadCount,
                   Int interOpThreadCount, Bool enableGraphOptimization,
                   Bool enableMemoryPattern, Bool enableProfiling,
                   Bool deterministicCompute, Bool enableCpuFallback,
                   Long maximumMemoryBytes,
                   Map<String, String> providerOptions) {
        if providers == null || providerOptions == null {
            throw "SessionOptions: null provider list or options"
        }
        if providers.length() == 0 {
            throw "SessionOptions: empty provider list"
        }
        if intraOpThreadCount < 0 || interOpThreadCount < 0 {
            throw "SessionOptions: negative thread count"
        }
        if maximumMemoryBytes < 0 {
            throw "SessionOptions: negative memory limit"
        }
        _providers = providers.copy()
        Int providerIndex = 0
        while providerIndex < _providers.length() {
            if _providers.get(providerIndex) == null {
                throw "SessionOptions: null provider"
            }
            Int scanIndex = providerIndex + 1
            while scanIndex < _providers.length() {
                if _providers.get(providerIndex) == _providers.get(scanIndex) {
                    throw "SessionOptions: duplicate provider"
                }
                scanIndex = scanIndex + 1
            }
            providerIndex = providerIndex + 1
        }
        Map<String, String> copiedOptions = [:]
        List<String> keys = providerOptions.keys()
        Int keyIndex = 0
        while keyIndex < keys.length() {
            String key = keys.get(keyIndex)
            String optionValue = providerOptions.get(key)
            if key == null || key == "" || key.trim() != key {
                throw "SessionOptions: invalid provider option key"
            }
            if optionValue == null {
                throw "SessionOptions: null provider option value"
            }
            copiedOptions.put(key, optionValue)
            keyIndex = keyIndex + 1
        }
        _intraOpThreadCount = intraOpThreadCount
        _interOpThreadCount = interOpThreadCount
        _enableGraphOptimization = enableGraphOptimization
        _enableMemoryPattern = enableMemoryPattern
        _enableProfiling = enableProfiling
        _deterministicCompute = deterministicCompute
        _enableCpuFallback = enableCpuFallback
        _maximumMemoryBytes = maximumMemoryBytes
        _providerOptions = copiedOptions
    }

    static SessionOptions defaults() {
        return new SessionOptions([ExecutionProvider.Cpu], 0, 0, true, true,
            false, false, true, 0, [:])
    }

    List<ExecutionProvider> providers() { return _providers.copy() }
    Int intraOpThreadCount() { return _intraOpThreadCount }
    Int interOpThreadCount() { return _interOpThreadCount }
    Bool enableGraphOptimization() { return _enableGraphOptimization }
    Bool enableMemoryPattern() { return _enableMemoryPattern }
    Bool enableProfiling() { return _enableProfiling }
    Bool deterministicCompute() { return _deterministicCompute }
    Bool enableCpuFallback() { return _enableCpuFallback }
    Long maximumMemoryBytes() { return _maximumMemoryBytes }
    Map<String, String> providerOptions() { return _providerOptions.copy() }

    String? providerOption(String key) {
        if key == null { throw "SessionOptions.providerOption: null key" }
        if key == "" { return null }
        return _providerOptions.get(key)
    }

    SessionOptions copy() {
        return new SessionOptions(_providers, _intraOpThreadCount,
            _interOpThreadCount, _enableGraphOptimization,
            _enableMemoryPattern, _enableProfiling, _deterministicCompute,
            _enableCpuFallback, _maximumMemoryBytes, _providerOptions)
    }

    String describe() {
        return "session options providers=" + str(_providers.length())
            + " intra=" + str(_intraOpThreadCount)
            + " inter=" + str(_interOpThreadCount)
            + " cpuFallback=" + str(_enableCpuFallback)
            + " memoryLimit=" + str(_maximumMemoryBytes)
    }
}
```
