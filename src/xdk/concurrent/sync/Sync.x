// Tier: T0；依赖：xdk.errors、xdk.tasks；稳定性：preview。
// xdk.sync —— S6-08 包骨架
//
// 说明：互斥、通道、原子原语契约（实现由 S5-03 运行时与语言面承担）。
// 依赖矩阵：本骨架不导入其他 xdk 单元（依赖方向由 S6 §2 冻结后再追加）。
// 稳定性：@preview（API 冻结前不承诺）。
package xdk.sync
