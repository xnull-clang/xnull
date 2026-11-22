# `Stopwatch`

| 项 | 值 |
| --- | --- |
| 类型 | `class Stopwatch` |
| 包 | `xdk.time` |
| 稳定性 | `preview` |
| 依赖 | `Duration` |

---

## 1. 定位

单调计时器：start/stop/reset/elapsed；用于耗时统计。

不做：挂钟时间、跨进程、精度承诺。

---

## 2. 设计逻辑

- 字段 `_startMono: Long`、`_elapsed: Long`、`_running: Bool`。
- start 记录 mono；stop 累加；reset 清零。
- elapsed 运行中 = 已累计 + (nowMono - startMono)；停止 = 已累计。
- 不可变？可变；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_startMono` | `Long` | 本次开始 mono |
| `_elapsed` | `Long` | 已累计毫秒 |
| `_running` | `Bool` | 是否运行 |

不变量：elapsed ≥0；running 时 startMono 有效。

---

## 4. 生命周期

可变；无 close；可 reset 重用。

---

## 5. 构造契约

`Stopwatch()` 未运行、elapsed 0。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `start` | 开始/继续 | 无 | `void` | 已运行 → no-op |
| `stop` | 停止 | 无 | `void` | 未运行 → no-op |
| `reset` | 清零 | 无 | `void` | 无 |
| `elapsed` | 耗时 | 无 | `Duration` | 无 |
| `elapsedMillis` | 毫秒 | 无 | `Long` | 无 |
| `isRunning` | 是否运行 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 单调时钟；
- 累计耗时；
- 状态机。

---

## 9. 需要的支撑

- 语言：class、Long、Bool；
- 运行时：`nowMono`；
- 接口：`Duration`。

---

## 10. 依赖的特性/接口/类

`Duration`、`runtime.nowMono`。

---

## 11. 所有权与并发

可变；非线程安全；无资源。

---

## 12. 示例与反例

正确：start → 工作 → stop → elapsed。  
反例：用 Stopwatch 做超时（用 deadline）；多任务共享；stop 后 start 期望重置（应 reset）。

---

## 13. 测试/场景义务

未启动 elapsed 0；start/stop；重复 start/stop；reset；elapsedMillis；运行中累计。

---

## 14. XNull 伪代码

```xnull
class Stopwatch {
    Long _startMono
    Long _elapsed
    Bool _running

    Stopwatch() {
        _startMono = 0
        _elapsed = 0
        _running = false
    }

    void start() {
        if _running { return }
        _startMono = nowMono()
        _running = true
    }

    void stop() {
        if !_running { return }
        _elapsed = _elapsed + (nowMono() - _startMono)
        _running = false
    }

    void reset() {
        _startMono = 0
        _elapsed = 0
        _running = false
    }

    Long elapsedMillis() {
        if _running {
            return _elapsed + (nowMono() - _startMono)
        }
        return _elapsed
    }

    Duration elapsed() {
        return new Duration(self.elapsedMillis())
    }

    Bool isRunning() { return _running }
}
```

---

## 15. 1.x 兼容边界（C7）

1.x `Stopwatch` 的行为：

```text
Stopwatch()        // 构造即开始
void start()       // 重新开始
Long stop()        // 停止并返回 elapsedMs
Long reset()       // 返回上次 elapsedMs 并重新开始
Long elapsedMs()
Duration elapsed()
Bool isRunning()
```

2.x 合同冻结为：

- `Stopwatch()` 不自动开始，`elapsedMillis() == 0`；
- `start()` 运行中 no-op；
- `stop()`/`reset()` 返回 `void`；
- 读数用 `elapsedMillis()`（1.x 名称 `elapsedMs` 迁移）。

迁移边界：1.x 公共字段 `startedAt/stoppedAt/running` 迁移到 `elapsedMillis()`/`isRunning()`，不保留公共字段；1.x `new Stopwatch()` 后立即计时 → 2.x 显式 `new Stopwatch().start()`；1.x `Long elapsed = watch.stop()` → 2.x `watch.stop(); Long elapsed = watch.elapsedMillis()`；1.x `reset()` 返回旧值 → 2.x 先读 `elapsedMillis()` 再 `reset()`。能力未删除，语义按 2.x 合同显式化。

测试义务：构造未启动；显式 start 后计时；stop/reset 的 2.x 语义；1.x 迁移示例；跨平台无差异。
