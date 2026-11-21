# `IntRange`

| 项 | 值 |
| --- | --- |
| 类型 | `class IntRange` |
| 包 | `xdk.collections` |
| 稳定性 | `preview` |
| 依赖 | `Iterator` |

---

## 1. 定位

整数区间：`[start, end)`，可设步长；用于循环/枚举/分页。

不做：泛型区间、浮点区间、无限流。

---

## 2. 设计逻辑

- 半开区间；`step > 0` 递增，`step < 0` 递减；`step != 0`。
- `length` 按步长计算；空区间长度 0。
- `contains` 按步长判断。
- `toList` 物化；`iterator` 返回单次迭代器。
- 不可变。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_start` | `Int` | 起始 |
| `_end` | `Int` | 结束（不含） |
| `_step` | `Int` | 步长，非 0 |

不变量：step != 0；区间方向与 step 一致才非空。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `IntRange(Int start, Int end)` | start/end | step=1 | 无 |
| `IntRange(Int start, Int end, Int step)` | start/end/step | step != 0 | step=0 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `start` | 起始 | 无 | `Int` | 无 |
| `end` | 结束 | 无 | `Int` | 无 |
| `step` | 步长 | 无 | `Int` | 无 |
| `length` | 元素数 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `contains` | 是否包含 | `Int value` | `Bool` | 无 |
| `toList` | 物化 | 无 | `List<Int>` | 无 |
| `iterator` | 迭代器 | 无 | `Iterator<Int>` | 无 |

---

## 8. 使用的技术

- 半开区间；
- 步长；
- 长度计算；
- 单次迭代器。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、List、闭包；
- 运行时：无；
- 接口：`Iterator`、`List`。

---

## 10. 依赖的特性/接口/类

`Iterator`、`List`。

---

## 11. 所有权与并发

不可变；可共享；iterator 单次消费。

---

## 12. 示例与反例

正确：`IntRange(0,5)` → 0..4；`IntRange(5,0,-1)` → 5..1。  
反例：step 0；期望 end 包含；反向区间用正 step。

---

## 13. 测试/场景义务

空/单/多；正/负 step；length；contains；toList；iterator 单次。

---

## 14. XNull 伪代码

```xnull
class IntRange {
    final Int _start
    final Int _end
    final Int _step

    IntRange(Int start, Int end) {
        _start = start
        _end = end
        _step = 1
    }

    IntRange(Int start, Int end, Int step) {
        if step == 0 {
            throw "IntRange: zero step"
        }
        _start = start
        _end = end
        _step = step
    }

    Int start() { return _start }
    Int end() { return _end }
    Int step() { return _step }

    Bool isEmpty() {
        if _step > 0 {
            return _start >= _end
        }
        return _start <= _end
    }

    Int length() {
        if self.isEmpty() { return 0 }
        if _step > 0 {
            return (_end - _start + _step - 1) / _step
        }
        return (_start - _end - _step - 1) / (0 - _step)
    }

    Bool contains(Int value) {
        if self.isEmpty() { return false }
        if _step > 0 {
            if value < _start || value >= _end { return false }
        } else {
            if value > _start || value <= _end { return false }
        }
        return (value - _start) % _step == 0
    }

    List<Int> toList() {
        List<Int> result = []
        Int value = _start
        if _step > 0 {
            while value < _end {
                result.push(value)
                value = value + _step
            }
        } else {
            while value > _end {
                result.push(value)
                value = value + _step
            }
        }
        return result
    }

    Iterator<Int> iterator() {
        Int current = _start
        return new Iterator<Int>(
            () -> {
                if _step > 0 {
                    return current < _end
                }
                return current > _end
            },
            () -> {
                Int value = current
                current = current + _step
                return value
            }
        )
    }
}
```
