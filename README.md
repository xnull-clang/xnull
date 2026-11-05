# XNull

**English** | [简体中文](#xnull中文说明)

**Explicit. Predictable. No implicit behavior.**

XNull is a new programming language, currently in active design. This repository publishes its specifications and the early stages of a compiler implementation. The approved baseline is published bilingually: Chinese originals under `spec/`, English translations under `spec/en/`.

---

## Core Design Principles

- **Compiler-decided memory management** — Source code never expresses reference strength. The compiler selects the memory management strategy for each object according to its decision table (DET-01), and the runtime executes it. What the language does is always predictable.
- **No accessor pattern** — There are no getters or setters. Properties are properties; behavior is behavior. The two are strictly separated at the syntax level.
- **Composition over inheritance** — Classes do not support override-based inheritance. Polymorphism is achieved exclusively through protocols.
- **Explicit error handling** — Errors are values expressed in the type system. No implicit exception propagation.

Deliberately excluded: overriding, abstract methods, reflection. Every design decision — including the reasons for each rejection — is documented with its rationale in the specifications.

## Status

| Part | Version | State |
|---|---|---|
| S1 Syntax | v3.3.0 | Approved |
| S2 Object Programming | v3.3.0 | Approved |
| S3 Memory Management | v3.0.0 | Approved |
| S4 Error Handling | v1.0.0 | Approved |
| S5 Runtime Tasks & Concurrency | v1.0.0 | Approved |
| S6 Standard Library (XDK) | v1.1.0 | Approved |
| S7 FFI | v1.0.0 | Approved |
| S8 Project Configuration | v5.2.0 | Approved |
| Compiler (Go) | — | Frontend in progress (lexer / parser) |

## Repository Layout

```
├── spec/       # Language specifications (Chinese originals; English translations in spec/en)
├── impl/       # Compiler implementation (Go)
└── examples/   # Example programs (planned)
```

## Roadmap

1. **Minimal closed loop** — a C backend that compiles one complete program end to end
2. **Incremental completion** — driven by the conformance test ledger
3. **Self-hosting** — the compiler rewritten in XNull

## Contributing

- **Welcome**: design discussions and feedback on any specification chapter (via Issues)
- **Not yet**: implementation PRs (will open after the frontend passes the conformance tests)

## License

This repository uses **dual licensing**, split by content type:

| Content | License |
|---|---|
| Specifications & documents (`spec/`) | [CC BY 4.0](./LICENSE-docs.md) |
| Code (`impl/`, `examples/`) | [Apache-2.0](./LICENSE) |

- You may freely quote, translate, and write tutorials about the specifications with attribution to **XNull Project — github.com/xnull-clang/xnull**.
- The language name and logo are not covered by either license and may not be used to name or promote derivative language projects.

---

# XNull（中文说明）

[English](#xnull) | **简体中文**

**显式 · 可预测 · 拒绝隐式。**

XNull 是一门处于设计阶段的新编程语言。本仓库公开其语言规范与编译器实现的早期进展。

## 核心设计主张

- **内存管理由编译器决定**：源码不表达引用强度。编译器按判定表（DET-01）为每个对象选择内存管理方式，运行时执行——语言行为始终可预测。
- **无访问器模式**：不存在 getter/setter。属性与行为在语法上严格分离。
- **组合优先于继承**：类不支持继承复写，多态只通过协议（protocol）实现。
- **显式错误处理**：错误是类型系统表达的值，不存在隐式异常传播。

明确不加：覆写、抽象方法、反射。每个设计决策（含拒绝理由）均随规范条款记录在规范文档中。

## 当前状态

| 部分 | 版本 | 状态 |
|---|---|---|
| S1 基础语法 | v3.3.0 | 正式 |
| S2 对象编程 | v3.3.0 | 正式 |
| S3 内存管理 | v3.0.0 | 正式 |
| S4 错误处理 | v1.0.0 | 正式 |
| S5 运行时任务与并发 | v1.0.0 | 正式 |
| S6 标准库 XDK | v1.1.0 | 正式 |
| S7 FFI | v1.0.0 | 正式 |
| S8 工程配置 | v5.2.0 | 正式 |
| 编译器（Go） | — | 前端开发中（词法 / 语法分析） |

## 仓库结构

```
├── spec/       # 语言规范（中文母本；英译见 spec/en）
├── impl/       # 编译器实现（Go）
└── examples/   # 示例程序（规划中）
```

## 路线图

1. **最小闭环**：C 后端跑通第一个完整程序
2. **增量补齐**：按一致性用例台账推进
3. **自举**：编译器改用 XNull 编写

## 参与

- **欢迎**：规范设计讨论与各章节反馈（通过 Issue）
- **暂不接收**：实现类 PR（前端通过一致性用例后开放）

## 许可证

本仓库采用**双许可证**，按内容类型划分：

| 内容 | 许可证 |
|---|---|
| 规范与文档（`spec/`） | [CC BY 4.0](./LICENSE-docs.md) |
| 代码（`impl/`、`examples/`） | [Apache-2.0](./LICENSE) |

- 规范可自由引用、翻译、撰写教程，但须署名 **XNull Project — github.com/xnull-clang/xnull**。
- 语言名称与 Logo 不在上述许可范围内，不得用于命名或推广衍生语言项目。
