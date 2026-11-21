# `Sequences`

| 项 | 值 |
| --- | --- |
| 类型 | `class Sequences` |
| 包 | `xdk.functional` |
| 稳定性 | `preview` |
| 依赖 | `Seq`、`List` |

---

## 1. 定位

序列生成静态入口：整数区间、重复、生成器、迭代、拼接、展平、可空转换。

不做：无限序列（X）、随机序列、并行生成、惰性生成。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- 所有生成器 eager，返回 `Seq` 快照。
- `range` 左闭右开；`rangeStep` 支持负步长，步长不能为 0。
- 生成次数必须非负；负数 panic。
- `generate`/`iterate` 的闭包不得返回 null 以外的非法值；返回 null 按元素类型允许时保留。
- 无 close；可并发。

---

## 3. 表示与不变量

无实例字段。

不变量：返回的 `Seq` 长度等于请求次数/区间大小；`rangeStep` 不包含 `endExclusive`；拼接保持左右顺序。

---

## 4. 生命周期

静态命名空间；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Sequences()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `range` | 整数区间 | `Int start, Int endExclusive` | `Seq<Int>` | 无 |
| `rangeStep` | 带步长区间 | `Int start, Int endExclusive, Int step` | `Seq<Int>` | step=0 → panic |
| `repeatValue` | 重复值 | `T value, Int count` | `Seq<T>` | count<0 → panic |
| `generate` | 生成器 | `Int count, T() supplier` | `Seq<T>` | count<0/null → panic |
| `iterate` | 迭代 | `T seed, Int count, T(T) next` | `Seq<T>` | count<0/null → panic |
| `concat` | 拼接 | `Seq<T> left, Seq<T> right` | `Seq<T>` | null → panic |
| `flatten` | 展平 | `List<List<T>> nested` | `Seq<T>` | null 内层 → panic |
| `fromNullable` | 可空转序列 | `T? value` | `Seq<T>` | 无 |

说明：

- `range(5, 5)` 为空；`range(5, 1)` 为空。
- `rangeStep(0, 10, 3)` → `[0,3,6,9]`；`rangeStep(10, 0, -3)` → `[10,7,4,1]`。
- `iterate(seed, 0, next)` 为空；`count=1` 只含 seed。
- `flatten` 跳过空内层，不跳过 null 元素。

---

## 8. 使用的技术

- 整数区间；
- 闭包生成；
- 列表拼接；
- 泛型静态方法。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、List、Seq、函数类型；
- 运行时：无；
- 接口：`Seq`。

---

## 10. 依赖的特性/接口/类

`Seq`、`List`。

---

## 11. 所有权与并发

无状态；返回独立快照；可并发；闭包由调用方保证线程安全。

---

## 12. 示例与反例

正确：`Sequences.range(0, 10).map((Int i) -> i * 2)`。  
反例：`rangeStep(0,10,0)`；负数 count；依赖 range 包含 end；生成器返回共享可变对象并并发修改。

---

## 13. 测试/场景义务

正/负步长；空区间；单元素；count 0/1/N；generate 副作用次数；iterate 序列；concat 空/非空；flatten 空内层；fromNullable null/非 null；溢出边界。

---

## 14. XNull 伪代码

```xnull
class Sequences {
    private Sequences() {
    }

    static Seq<Int> range(Int start, Int endExclusive) {
        return Sequences.rangeStep(start, endExclusive, 1)
    }

    static Seq<Int> rangeStep(Int start, Int endExclusive, Int step) {
        if step == 0 { throw "Sequences.rangeStep: zero step" }
        List<Int> result = []
        Int value = start
        if step > 0 {
            while value < endExclusive {
                result.push(value)
                value = value + step
            }
        } else {
            while value > endExclusive {
                result.push(value)
                value = value + step
            }
        }
        return new Seq<Int>(result)
    }

    static Seq<T> repeatValue<T>(T value, Int count) {
        if count < 0 { throw "Sequences.repeatValue: negative count" }
        List<T> result = []
        Int index = 0
        while index < count {
            result.push(value)
            index = index + 1
        }
        return new Seq<T>(result)
    }

    static Seq<T> generate<T>(Int count, T() supplier) {
        if count < 0 { throw "Sequences.generate: negative count" }
        if supplier == null { throw "Sequences.generate: null supplier" }
        List<T> result = []
        Int index = 0
        while index < count {
            result.push(supplier())
            index = index + 1
        }
        return new Seq<T>(result)
    }

    static Seq<T> iterate<T>(T seed, Int count, T(T) next) {
        if count < 0 { throw "Sequences.iterate: negative count" }
        if next == null { throw "Sequences.iterate: null next" }
        List<T> result = []
        if count == 0 { return new Seq<T>(result) }
        T value = seed
        result.push(value)
        Int index = 1
        while index < count {
            value = next(value)
            result.push(value)
            index = index + 1
        }
        return new Seq<T>(result)
    }

    static Seq<T> concat<T>(Seq<T> left, Seq<T> right) {
        if left == null || right == null {
            throw "Sequences.concat: null argument"
        }
        List<T> result = left.toList()
        result.addAll(right.toList())
        return new Seq<T>(result)
    }

    static Seq<T> flatten<T>(List<List<T>> nested) {
        if nested == null { throw "Sequences.flatten: null nested" }
        List<T> result = []
        Int index = 0
        while index < nested.length() {
            List<T> inner = nested.get(index)
            if inner == null { throw "Sequences.flatten: null inner list" }
            Int part = 0
            while part < inner.length() {
                result.push(inner.get(part))
                part = part + 1
            }
            index = index + 1
        }
        return new Seq<T>(result)
    }

    static Seq<T> fromNullable<T>(T? value) {
        List<T> result = []
        if value != null { result.push(value) }
        return new Seq<T>(result)
    }
}
```
