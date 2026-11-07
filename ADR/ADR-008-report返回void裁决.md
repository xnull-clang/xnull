# ADR-008 XDK 规范冲突裁决：`report` 返回 void

> 日期：2026-11-08 05:15
> 状态：生效
> 依据：S4 §2.1 与 S6 §4.1 冲突；S4 门已签（`收件箱/门/S4门.md`）；QA XDK-03 判定 BLOCKED

## 背景

- S4 §2.1：`report` 签名 `<E: Error>(Result<T,E>) -> void`；
- S6 §4.1 定案 3-a-1：要求 `report` 返回原 `Result`（便于链式）；
- `impl/lib/xdk/errors.x` 按 S4 返回 `void`，导致 XDK-03 无法签 PASS。

## 决定

1. **`report` 统一返回 `void`**，S4 §2.1 为准；S6 §4.1 的“返回原 Result”按编辑性修订改为 `void`，不构成 API 变更。
2. 需要链式观测时，调用方显式先 `report` 再返回原 `Result`，不提供隐式链式语法。
3. `errors.x` 保持 `void`；XDK-03 可据此解除 BLOCKED 并重新验收。

## 后果

- S6 修订说明需记录该编辑性变更；
- 所有依赖 `report` 返回值的用例必须改为 `void` 形态；
- 不改变 S4 已签行为与证据。
