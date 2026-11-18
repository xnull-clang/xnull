// Tier: T0；依赖：xdk.errors、xdk.runtime；稳定性：preview。
// xdk.tasks —— S6-08 包骨架
//
// 说明：任务、任务组、上下文契约（实现由 S5 运行时与解释器/编译器桥接承担）。
// 依赖矩阵：本骨架不导入其他 xdk 单元（依赖方向由 S6 §2 冻结后再追加）。
// 稳定性：@preview（API 冻结前不承诺）。
//
// 已验收面（W2，mini）：
//   Context    background() / isCancelled() / cancel()
//   TaskGroup  create(parent) / spawn(Result<T,TaskError>()) / cancel() / close()
//   Task<T>    join() / joinDeadline(deadlineMonoMs)
// 运行时契约：close 取消组上下文并等待所有任务结束，返回首个非取消错误；
// joinDeadline 超时返回 Err 且不消费任务结果，任务继续执行直到取消或完成。
package xdk.tasks
