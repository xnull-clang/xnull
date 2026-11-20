# xdk.sync —— T0 同步原语 v1.0

| 项 | 值 |
| --- | --- |
| 包 | `xdk.sync` |
| 层级 | T0 |
| 稳定性 | `preview` |
| 依赖 | `xdk.errors`、`xdk.tasks` |
| 被依赖 | log、config、metrics（T1） |
| 对应源码 | `src/xdk/concurrent/sync/Sync.x`（运行时绑定） |
| 当前状态 | Verified（Atomic/Mutex/Channel<Int/Long/Bool/Char/String/Bytes/class/protocol/nullable>） |

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
    Result<void, TaskError> withLock(void(T) body)
}

class Channel<T> {
    Channel(Int capacity)
    Result<void, CancelledError> send(T value)
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
- `Channel<T>` 已覆盖 `Int`、`Long`、`Bool`、`Char`、`String`、`Bytes`、
  class、协议和可空元素；`Bytes`/class 等指针元素按引用传递。
- `Double`、`Int128`、`Result` 等值对象元素尚未支持，归入 T0-X；
  不得用指针转换伪装。
- `send` 满/`receive` 空时可阻塞并接受任务 Context；取消返回 `Err(CancelledError)`，不消费值。
- `close` 幂等；关闭后 `send/receive` 返回 `Err`，队列剩余元素丢弃。
- Atomic 操作是顺序一致；不承诺无锁实现。

## 3. 测试义务

- Mutex 两次 withLock 的可见性；
- Channel send/receive/close/满/空；
- 取消中的 send/receive；
- Atomic load/store/CAS 成功与失败；
- base/full 输出一致。

场景：`xdk_mutex.x`、`xdk_channel.x`、`xdk_channel_typed.x`、`xdk_sync_atomic.x`、`xdk_sync_ref.x`、`xdk_cancel.x`。

## 4. 后续（T0-X/T1）

- `Double`/`Int128`/`Result` 等值对象元素；
- RwLock/Semaphore/WaitGroup/Once/Barrier；
- `select`/超时收发；
- 并发容器。
