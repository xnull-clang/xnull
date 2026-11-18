// Tier: T0；依赖：xdk.errors、xdk.tasks；稳定性：preview。
// xdk.sync —— S6-08 包骨架
//
// 说明：互斥、通道、原子原语契约（实现由 S5-03 运行时与语言面承担）。
// 依赖矩阵：本骨架不导入其他 xdk 单元（依赖方向由 S6 §2 冻结后再追加）。
// 稳定性：@preview（API 冻结前不承诺）。
//
// 已验收面（W2；legacy 差分缺口单独记录）：
//   AtomicInt/AtomicBool  load/store/compareExchange(cas)
//   AtomicRef<T>          load/store/compareExchange
//   Mutex<T>              Mutex(data) + withLock(T) -> Result<void,TaskError>
//   Channel<Int>          Channel(cap) + send/receive -> Result<...,CancelledError>
//                         + close()
// 运行时契约：withLock 的闭包在持锁状态执行；channel 的 send/receive 接受
// 任务上下文，取消时返回 Err 而不消费值；close 幂等并丢弃队列剩余元素。
package xdk.sync
