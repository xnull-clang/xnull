# `Test`

| 项 | 值 |
| --- | --- |
| 类型 | `class Test` |
| 包 | `xdk.test` |
| 稳定性 | `preview` |
| 依赖 | `TestContext`、`Error`、`Result`、`Unit`、`List`、`String`、`Long`、`trim` |

---

## 1. 定位

不可变测试定义：名称、标签、超时毫秒、body 函数值。

不做：执行、注册、结果保存、日志缓冲、超时强制终止、标签继承、测试发现。

`Test` 只描述“要运行什么”，执行归 `TestRunner`。

---

## 2. 设计逻辑

- 字段：名称、标签列表、超时毫秒、body。
- 构造时校验：名称去首尾空白后非空；标签非 null、去空白后非空、同一测试内不重复；超时 `>= 0`；body 非 null。
- 标签在构造时复制并规范化；`tags()` 返回副本，外部修改不影响测试。
- `timeoutMillis == 0` 表示不设超时；`> 0` 表示单测试截止。
- body 类型为 `Result<Unit, Error>(TestContext)`；成功用 `Ok(unit)`。
- 不可变；body 捕获的外部可变状态不属于 `Test` 的不可变性保证。
- 无全局注册；构造 `Test` 不会自动加入任何集合。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | final；去首尾空白后非空 |
| `_tags` | `List<String>` | 内部列表；去空白、拒绝重复、保持输入顺序 |
| `_timeoutMillis` | `Long` | final；`>= 0`，0 表示无超时 |
| `_body` | `Result<Unit, Error>(TestContext)` | final；非 null |

不变量：名称规范化后非空；标签非空且唯一；超时非负；body 非 null；`tags()` 只返回副本。

---

## 4. 生命周期

构造后长期有效；不可变；无 close；无资源；可被多个 `TestSuite` 引用，也可被同一 runner 多次运行。重复运行是否安全取决于 body 捕获的外部状态。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Test(String name, List<String> tags, Long timeoutMillis, Result<Unit, Error>(TestContext) body)` | 全部 | name 去空白非空；tags 非 null、元素非空白且不重复；timeoutMillis ≥ 0；body 非 null | null/空名称/空标签/重复标签/负超时/ null body → panic |

说明：

- 名称和标签存储规范化后的值；输入两侧空白被去除。
- 不提供默认参数；无标签时传 `[]`，无超时传 `0`。
- 构造器不执行 body，不访问全局状态。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 测试名 | 无 | `String` | 无 |
| `tags` | 标签快照 | 无 | `List<String>` | 无 |
| `timeoutMillis` | 超时毫秒 | 无 | `Long` | 无 |
| `body` | body 函数值 | 无 | `Result<Unit, Error>(TestContext)` | 无 |
| `hasTag` | 是否含标签 | `String tag` | `Bool` | null tag → panic；空白返回 false |

说明：

- `tags()` 每次返回新列表；修改返回值不改变测试。
- `hasTag` 对标签做去空白比较，大小写敏感。
- `timeoutMillis() == 0` 表示 `TestRunner` 不设截止。
- `body` 返回函数值本身；调用方负责传入非 null `TestContext`。
- `Test` 不提供 `run`；执行由 `TestRunner` 负责。

---

## 8. 使用的技术

- 不可变对象；
- 防御性复制；
- 输入规范化；
- 函数值；
- 构造期校验。

---

## 9. 需要的支撑

- 语言：class、final 字段、泛型容器、函数类型、Bool、Long、String、Result、Unit；
- 运行时：无；
- 接口：`TestContext`、`Error`、`trim`。

---

## 10. 依赖的特性/接口/类

`TestContext`、`Error`、`Result`、`Unit`、`List`、`String`、`Long`、`trim`。

---

## 11. 所有权与并发

引用语义；构造后不可变；`tags()` 返回副本；可跨任务共享。body 捕获的外部状态可能可变，需调用方保证；`Test` 自身不提供同步。

---

## 12. 示例与反例

正确：

```xnull
Test test = new Test("adds", ["unit", "fast"], 1000, (TestContext context) -> {
    Result<Unit, Error> checked = Assert.equals(2, 1 + 1, "")
    if checked.isErr() { return Err(checked.error()) }
    return Ok(unit)
})
```

反例：空名称；`timeoutMillis` 为负；重复标签；构造后修改传入的标签列表并期望测试变化；把 `Test` 当运行器；依赖 body 捕获的可变状态在多次运行间重置。

---

## 13. 测试/场景义务

名称去空白/空/空白；标签 null/空/重复/顺序/副本独立性；`timeoutMillis` 0/正值/负值；body null；`hasTag` 大小写与空白；body 接收 `TestContext`；同一 `Test` 多次运行；不可变字段读取。

---

## 14. XNull 伪代码

```xnull
class Test {
    final String _name
    final List<String> _tags
    final Long _timeoutMillis
    final Result<Unit, Error>(TestContext) _body

    Test(String name, List<String> tags, Long timeoutMillis,
         Result<Unit, Error>(TestContext) body) {
        if name == null || tags == null || body == null {
            throw "Test: null argument"
        }
        if timeoutMillis < 0 {
            throw "Test: negative timeout"
        }
        String normalizedName = trim(name)
        if normalizedName == "" {
            throw "Test: empty name"
        }
        _name = normalizedName
        _tags = []
        Int index = 0
        while index < tags.length() {
            String tag = tags.get(index)
            if tag == null {
                throw "Test: null tag"
            }
            String normalizedTag = trim(tag)
            if normalizedTag == "" {
                throw "Test: empty tag"
            }
            if _tags.contains(normalizedTag) {
                throw "Test: duplicate tag"
            }
            _tags.push(normalizedTag)
            index = index + 1
        }
        _timeoutMillis = timeoutMillis
        _body = body
    }

    String name() {
        return _name
    }

    List<String> tags() {
        return _tags.copy()
    }

    Long timeoutMillis() {
        return _timeoutMillis
    }

    Result<Unit, Error>(TestContext) body() {
        return _body
    }

    Bool hasTag(String tag) {
        if tag == null {
            throw "Test.hasTag: null tag"
        }
        String normalized = trim(tag)
        if normalized == "" {
            return false
        }
        return _tags.contains(normalized)
    }
}
```
