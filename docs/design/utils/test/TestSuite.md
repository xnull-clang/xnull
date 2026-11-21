# `TestSuite`

| 项 | 值 |
| --- | --- |
| 类型 | `class TestSuite` |
| 包 | `xdk.test` |
| 稳定性 | `preview` |
| 依赖 | `Test`、`List`、`String`、`Bool`、`Int`、`trim` |

---

## 1. 定位

命名的、有序的、测试名唯一的 `Test` 集合。

不做：执行、结果保存、全局注册、自动发现、标签索引、并发修改同步、suite 级超时。

执行归 `TestRunner`；`TestSuite` 不调用 body，也不持有 `TestResult`。

---

## 2. 设计逻辑

- 字段：suite 名称、`List<Test>`。
- `add` 追加一个测试；测试名重复是合同错误。
- `addAll` 先完整校验输入（非 null、无重复、与现有不重复），再一次性追加；失败不产生部分写入。
- `filter(tag)` 返回新的 `TestSuite` 快照，保留原 suite 名称和测试顺序；过滤结果与原 suite 独立。
- `tests()` 返回副本；修改副本不影响 suite。
- `length()` 返回当前测试数。
- 不是线程安全的容器；应在运行前构建完成；`tests()` 的快照用于运行期只读迭代。
- 无全局注册表；`TestSuite` 由调用方显式持有。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | final；去首尾空白后非空 |
| `_tests` | `List<Test>` | 插入顺序；测试名唯一；元素非 null |

不变量：名称非空；测试名在 suite 内唯一；顺序稳定；`tests()` 不暴露内部列表。

---

## 4. 生命周期

`TestSuite(name)` 创建空集合；`add`/`addAll` 构建；`filter` 产生新快照；无 close；无资源。

suite 可在多次运行间复用；运行期间不应并发修改。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TestSuite(String name)` | name | 去首尾空白后非空 | null/空白 → panic |

初始为空集合；不提供隐式默认 suite。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | suite 名 | 无 | `String` | 无 |
| `add` | 追加测试 | `Test test` | `TestSuite`（self） | null/重名 → panic |
| `addAll` | 批量追加 | `List<Test> tests` | `TestSuite`（self） | null/重名 → panic；失败不部分写入 |
| `filter` | 按标签快照 | `String tag` | `TestSuite` | null/空白 tag → panic |
| `tests` | 测试快照 | 无 | `List<Test>` | 无 |
| `length` | 测试数 | 无 | `Int` | 无 |

说明：

- `add` 与 `addAll` 返回 self，支持链式构建；返回值不是新 suite。
- `addAll` 的输入列表与已有测试都可能含重名；任一重复都会在写入前 panic。
- `filter` 返回的新 suite 同名、同顺序，只包含 `hasTag(tag)` 为 true 的测试；没有匹配时返回空 suite。
- `filter` 是快照，不是实时视图；之后向原 suite 添加测试不会影响已过滤 suite。
- `tests()` 返回副本；修改副本不改变 suite。
- `TestSuite` 不提供 `run`/`results`；运行与结果由 `TestRunner` 拥有。

---

## 8. 使用的技术

- 有序动态列表；
- 线性重名校验；
- 批量校验后提交；
- 防御性快照；
- 标签过滤。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、String、Bool、Int、`trim`；
- 运行时：无；
- 接口：`Test`、`Test.hasTag`、`Test.name`。

---

## 10. 依赖的特性/接口/类

`Test`、`List`、`String`、`Bool`、`Int`、`trim`。

---

## 11. 所有权与并发

引用语义；可变集合；非线程安全。构建阶段由单线程持有；运行阶段用 `tests()` 快照只读迭代。`filter` 返回独立副本，可单独修改。

---

## 12. 示例与反例

正确：

```xnull
TestSuite suite = new TestSuite("math")
suite.add(new Test("adds", ["unit"], 0, body))
suite.addAll([new Test("subtracts", ["unit"], 0, otherBody)])
TestSuite fast = suite.filter("fast")
```

反例：向同一 suite 添加两个同名测试；把 `filter` 当实时视图；在 runner 迭代时并发 `add`；把结果塞回 suite；直接调用 suite 执行测试。

---

## 13. 测试/场景义务

名称 null/空白；初始为空；add 顺序；重名拒绝；addAll 批量重名拒绝与原子性；filter 有无匹配/顺序/独立性；tests 副本独立性；length；同名 suite；重复运行；并发修改文档边界。

---

## 14. XNull 伪代码

```xnull
class TestSuite {
    final String _name
    final List<Test> _tests = []

    TestSuite(String name) {
        if name == null {
            throw "TestSuite: null name"
        }
        String normalized = trim(name)
        if normalized == "" {
            throw "TestSuite: empty name"
        }
        _name = normalized
    }

    String name() {
        return _name
    }

    Int length() {
        return _tests.length()
    }

    List<Test> tests() {
        return _tests.copy()
    }

    TestSuite add(Test test) {
        if test == null {
            throw "TestSuite.add: null test"
        }
        if self.containsName(test.name()) {
            throw "TestSuite.add: duplicate name"
        }
        _tests.push(test)
        return self
    }

    TestSuite addAll(List<Test> tests) {
        if tests == null {
            throw "TestSuite.addAll: null list"
        }
        List<Test> staged = []
        Int index = 0
        while index < tests.length() {
            Test test = tests.get(index)
            if test == null {
                throw "TestSuite.addAll: null test"
            }
            if self.containsName(test.name()) || stagedContains(staged, test.name()) {
                throw "TestSuite.addAll: duplicate name"
            }
            staged.push(test)
            index = index + 1
        }
        _tests.addAll(staged)
        return self
    }

    TestSuite filter(String tag) {
        if tag == null {
            throw "TestSuite.filter: null tag"
        }
        String normalized = trim(tag)
        if normalized == "" {
            throw "TestSuite.filter: empty tag"
        }
        TestSuite result = new TestSuite(_name)
        Int index = 0
        while index < _tests.length() {
            Test test = _tests.get(index)
            if test.hasTag(normalized) {
                result.add(test)
            }
            index = index + 1
        }
        return result
    }

    private Bool containsName(String name) {
        Int index = 0
        while index < _tests.length() {
            if _tests.get(index).name() == name {
                return true
            }
            index = index + 1
        }
        return false
    }

    private static Bool stagedContains(List<Test> tests, String name) {
        Int index = 0
        while index < tests.length() {
            if tests.get(index).name() == name {
                return true
            }
            index = index + 1
        }
        return false
    }
}
```
