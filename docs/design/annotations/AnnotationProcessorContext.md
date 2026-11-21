# `AnnotationProcessorContext`

| 项 | 值 |
| --- | --- |
| 类型 | `class AnnotationProcessorContext` |
| 包 | `xdk.annotations` |
| 稳定性 | `preview` |
| 依赖 | `AnnotationProcessorPhase`、`AnnotationElement`、`List`、`Map`、`String`、`Bool` |

---

## 1. 定位

注解处理器单次调用的不可变上下文：当前阶段、可见元素、构建选项。

不做：不做文件系统、不做网络、不做运行时反射、不做处理器注册、不做增量缓存、不做依赖注入。

---

## 2. 设计逻辑

- 每次阶段调用构造一个上下文；上下文只覆盖当前阶段可见的已解析元素。
- `phase` 决定处理器应执行的行为；处理器不得假设未声明阶段会被调用。
- `elements` 是 `AnnotationElement` 的有序快照；顺序由编译器/调度器决定，处理器不得依赖跨运行稳定顺序。
- `options` 是构建清单/命令行传入的处理器选项快照；键非空、值非 null，值可以为空串。
- `optionOr` 的 fallback 只在键缺失时使用；空串是合法值，不触发 fallback。
- 上下文不可变；处理器不能通过它修改元素、选项或阶段。
- 上下文只在构建期存在，不得保存到运行时全局状态。
- 处理器不得从上下文推断未提供的文件、网络或反射能力。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_phase` | `AnnotationProcessorPhase` | 当前阶段，final，非 null |
| `_elements` | `List<AnnotationElement>` | 元素快照；内部副本 |
| `_options` | `Map<String, String>` | 选项快照；内部副本 |

不变量：

- `phase` 非 null。
- `elements` 非 null；元素非 null；保持输入顺序；构造后不再修改。
- `options` 非 null；键非空；值非 null；构造后不再修改。
- `elements()` 与 `options()` 返回副本。
- 不存在可变全局状态；不存在运行时生命周期。
- 同一上下文可被同一阶段的多个只读检查共享。

---

## 4. 生命周期

由处理器调度器在构建期创建；一次阶段调用内有效；无 close；无资源；构建结束后回收；不得跨构建缓存上下文对象。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AnnotationProcessorContext(AnnotationProcessorPhase phase, List<AnnotationElement> elements, Map<String, String> options)` | 全部 | phase 非 null；elements 非 null、元素非 null；options 非 null、键非空、值非 null | null/含 null/空键 → panic |

说明：

- `elements` 在构造时逐项复制；调用方之后修改原列表不影响上下文。
- `options` 在构造时逐项复制；键保持原样，不做大小写或空白归一化。
- 选项值允许空串；缺失与空串语义不同。
- 不校验选项名是否属于某个处理器；未知选项由处理器自行决定忽略或报诊断。
- 不允许传入运行时资源句柄、文件句柄或网络对象。

---

## 6. 字段表

见 §3；字段私有、`final`。`_elements` 与 `_options` 保存内部副本。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `phase` | 当前阶段 | 无 | `AnnotationProcessorPhase` | 无 |
| `elements` | 元素快照 | 无 | `List<AnnotationElement>` | 无 |
| `options` | 选项快照 | 无 | `Map<String, String>` | 无 |
| `hasOption` | 选项是否存在 | `String name` | `Bool` | null/空 name → panic |
| `optionOr` | 取选项或兜底 | `String name, String fallback` | `String` | null/空 name 或 null fallback → panic |

说明：

- `elements()` 每次返回新列表；修改返回值不影响上下文。
- `options()` 每次返回新映射；键顺序不承诺。
- `hasOption` 对空串值返回 true；只有键缺失才返回 false。
- `optionOr` 在键存在时返回其值（包括空串）；缺失时返回 fallback。
- 不提供 `put`/`remove`/`addElement` 等修改方法。
- 不提供 `files`/`network`/`reflection` 访问器；处理器合同禁止这些能力。

---

## 8. 使用的技术

- 不可变上下文；
- 快照；
- 防御性复制；
- 阶段枚举；
- 选项映射；
- 编译期沙箱边界。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Map、String、Bool、String.trim；
- 编译器/构建系统：元素投影、阶段调度、选项传递；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

`AnnotationProcessorPhase`、`AnnotationElement`、`List`、`Map`、`String`、`Bool`。

被 `AnnotationProcessor.process` 接收。

---

## 11. 所有权与并发

- 引用语义对象，但构造后不可变。
- 可跨任务只读共享；无同步需求。
- `elements()`/`options()` 返回副本。
- 处理器不得把上下文保存到静态字段或跨构建缓存。
- 相等：没有值相等实现；`==` 是引用身份。

---

## 12. 示例与反例

正确：

```xnull
AnnotationProcessorContext context = new AnnotationProcessorContext(
    AnnotationProcessorPhase.Validate,
    [deviceElement, colorElement],
    ["strict": "true", "generatedPackage": ""]
)
Bool strict = context.optionOr("strict", "false") == "true"
Bool hasGeneratedPackage = context.hasOption("generatedPackage")
List<AnnotationElement> elements = context.elements()
```

反例：修改 `elements()` 返回值期望改变上下文；把空串选项当作缺失；在处理器里直接写文件/联网；把上下文保存到运行时单例；用上下文修改声明；依赖元素顺序跨构建稳定；用 `null` 作为选项键。

---

## 13. 测试/场景义务

- 阶段读回；
- 元素复制、空列表、含 null 拒绝；
- 选项复制、空值、未知键、含 null 键/值拒绝；
- `hasOption` 缺失/空串/普通值；
- `optionOr` 命中/缺失/空串/fallback；
- `elements()`/`options()` 副本独立性；
- 不可变/并发只读；
- 上下文不暴露文件/网络/反射能力。

---

## 14. XNull 伪代码

```xnull
class AnnotationProcessorContext {
    final AnnotationProcessorPhase _phase
    final List<AnnotationElement> _elements
    final Map<String, String> _options

    AnnotationProcessorContext(AnnotationProcessorPhase phase,
                               List<AnnotationElement> elements,
                               Map<String, String> options) {
        if phase == null {
            throw "AnnotationProcessorContext: null phase"
        }
        if elements == null {
            throw "AnnotationProcessorContext: null elements"
        }
        if options == null {
            throw "AnnotationProcessorContext: null options"
        }
        _phase = phase
        _elements = []
        Int elementIndex = 0
        while elementIndex < elements.length() {
            AnnotationElement element = elements.get(elementIndex)
            if element == null {
                throw "AnnotationProcessorContext: null element"
            }
            _elements.push(element)
            elementIndex = elementIndex + 1
        }
        _options = [:]
        List<String> names = options.keys()
        Int optionIndex = 0
        while optionIndex < names.length() {
            String name = names.get(optionIndex)
            if name == null || trim(name) == "" {
                throw "AnnotationProcessorContext: empty option name"
            }
            String value = options.get(name)
            if value == null {
                throw "AnnotationProcessorContext: null option value"
            }
            _options.put(name, value)
            optionIndex = optionIndex + 1
        }
    }

    AnnotationProcessorPhase phase() {
        return _phase
    }

    List<AnnotationElement> elements() {
        return _elements.copy()
    }

    Map<String, String> options() {
        Map<String, String> result = [:]
        List<String> names = _options.keys()
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            result.put(name, _options.get(name))
            index = index + 1
        }
        return result
    }

    Bool hasOption(String name) {
        if name == null || name == "" {
            throw "AnnotationProcessorContext.hasOption: empty name"
        }
        return _options.has(name)
    }

    String optionOr(String name, String fallback) {
        if name == null || name == "" {
            throw "AnnotationProcessorContext.optionOr: empty name"
        }
        if fallback == null {
            throw "AnnotationProcessorContext.optionOr: null fallback"
        }
        if _options.has(name) {
            return _options.get(name)
        }
        return fallback
    }
}
```
