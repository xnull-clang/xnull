# xdk.sync ——  同步原语 v1.1

> **1.x legacy**：本文件是 `xdk.sync` 兼容命名/旧状态账本，不是 2.x 公共包。2.x 统一使用 [`execution/`](execution/README.md) 的 `xdk.execution`；见 [`../PACKAGE-MAP.md`](../PACKAGE-MAP.md)。

> **状态（2026-11-21）**：本文件是  v1 包级设计/实现状态账本。
> 公开类型与方法形态以 [`core/`](README.md) 为准；状态汇总见 [`STATUS.md`](STATUS.md)；
> 本文件的 `当前状态`、源码路径与 K/X 明细继续保留。

| 项 | 值 |
| --- | --- |
| 包 | `xdk.sync` |
| 层级 |  |
| 稳定性 | `preview` |
| 依赖 | `xdk.errors`、`xdk.tasks` |
| 被依赖 | log、config、metrics（） |
| 对应源码 | `src/xdk/concurrent/sync/Sync.x`（运行时绑定） |
| 当前状态 | Verified（Atomic/Mutex/Channel<Int/Long/Bool/Char/Double/String/Bytes/class/protocol/nullable/Int128/Result>） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 数据锁 | 闭包内持锁访问 | `Mutex<T>` |
| CAP-2 通道 | 有界发送/接收/关闭 | `Channel<T>` |
| CAP-3 原子整数 | load/store/CAS | `AtomicInt` |
| CAP-4 原子布尔 | load/store/CAS | `AtomicBool` |
| CAP-5 原子引用 | load/store/CAS | `AtomicRef<T>` |

**非目标**：RwLock、Semaphore、WaitGroup、Once、Barrier、select、无锁容器。

## 2. 契约

```text
class Mutex<T> {
    Mutex(T value)
    Result<Unit, TaskError> withLock(void(T) body)
}

class Channel<T> {
    Channel(Int capacity)
    Result<Unit, CancelledError> send(T value)
    Result<T, CancelledError> receive()
    void close()
}

class AtomicInt {
    AtomicInt(Int initial)
    Int load()
    void store(Int value)
    Bool compareExchange(Int expected, Int replacement)
}
```

- `withLock` 的闭包在持锁状态执行；返回 `Err` 也会释放锁。
- 不提供裸 lock/unlock。
- `Channel(capacity)` 要求 `capacity >= 0`；0 为同步通道。
- `Channel<T>` 已覆盖 `Int`、`Long`、`Bool`、`Char`、`Double`、`String`、
  `Bytes`、class、协议、可空元素、`Int128` 和 `Result<...>`。
- `Bytes`/class 等指针元素按引用传递；`Double` 按 64 位位模式传输。
- `Int128` 与 `Result<...>` 使用堆装箱元素，通道关闭/发送失败时释放，
  不把 128 位值或结构体伪装成普通指针。
- `send` 满/`receive` 空时可阻塞并接受任务 Context；取消返回 `Err(CancelledError)`，不消费值。
- `close` 幂等；关闭后 `send/receive` 返回 `Err`，队列剩余元素丢弃。
- Atomic 操作是顺序一致；不承诺无锁实现。

## 3. 测试义务

- Mutex 两次 withLock 的可见性；
- Channel send/receive/close/满/空；
- Int128/Result 装箱元素的往返、关闭与发送失败；
- 取消中的 send/receive；
- Atomic load/store/CAS 成功与失败；
- base/full 输出一致。

场景：`xdk_mutex.x`、`xdk_channel.x`、`xdk_channel_typed.x`、`xdk_sync_atomic.x`、`xdk_sync_ref.x`、`xdk_cancel.x`。

## 4. 后续（X/）

- RwLock/Semaphore/WaitGroup/Once/Barrier；
- `select`/超时收发；
- 并发容器。
