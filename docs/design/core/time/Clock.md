# `Clock`

| 项 | 值 |
| --- | --- |
| 类型 | `class Clock` |
| 包 | `xdk.time` |
| 稳定性 | `preview` |
| 依赖 | `Instant` |

---

## 1. 定位

可替换时钟：系统墙钟或固定时刻；用于测试/确定性。

不做：调度器、单调时钟（用 `nowMono`/`Stopwatch`）、NTP。

---

## 2. 设计逻辑

- 字段 `_isFixed: Bool`、`_fixedMillis: Long`。
- `system()` 每次读墙钟；`fixed(Instant)` 恒返回固定时刻。
- 不可变；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_isFixed` | `Bool` | 是否固定 |
| `_fixedMillis` | `Long` | 固定 epoch 毫秒 |

不变量：fixed 时使用 `_fixedMillis`；否则读墙钟。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Clock.system()` | 无 | 系统墙钟 | 无 |
| `Clock.fixed(Instant instant)` | instant | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `now` | 当前 Instant | 无 | `Instant` | 无 |
| `nowMillis` | 当前毫秒 | 无 | `Long` | 无 |
| `isFixed` | 是否固定 | 无 | `Bool` | 无 |
| `fixedInstant` | 固定时刻 | 无 | `Instant?` | 无 |

---

## 8. 使用的技术

- 系统墙钟；
- 固定时刻；
- 测试替换。

---

## 9. 需要的支撑

- 语言：class、Long、Bool；
- 运行时：`nowWall`；
- 接口：`Instant`。

---

## 10. 依赖的特性/接口/类

`Instant`、`runtime.nowWall`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：测试用 `Clock.fixed(Instant.ofEpochMillis(0))`。  
反例：用 Clock 做超时（用 mono）；期望 fixed 自动前进；多线程修改 Clock。

---

## 13. 测试/场景义务

system 非负；fixed 恒定；nowMillis；isFixed；fixedInstant；并发共享。

---

## 14. XNull 伪代码

```xnull
class Clock {
    final Bool _isFixed
    final Long _fixedMillis

    Clock(Bool isFixed, Long fixedMillis) {
        _isFixed = isFixed
        _fixedMillis = fixedMillis
    }

    static Clock system() {
        return new Clock(false, 0)
    }

    static Clock fixed(Instant instant) {
        if instant == null { throw "Clock.fixed: null instant" }
        return new Clock(true, instant.epochMillis())
    }

    Instant now() {
        if _isFixed {
            return new Instant(_fixedMillis)
        }
        return new Instant(nowWall())
    }

    Long nowMillis() {
        return self.now().epochMillis()
    }

    Bool isFixed() { return _isFixed }

    Instant? fixedInstant() {
        if !_isFixed { return null }
        return new Instant(_fixedMillis)
    }
}
```
