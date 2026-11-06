# README Upgrade Draft v2 — Quick-Start & Comparison (Bilingual)

> **T3 修订后定稿版**（替代 v1 的 divide 示例方案；技术表述已按回执-T3 收紧）。
> 插入位置：`xnull/README.md` 双语两部分的「核心设计主张」之后；对比表与「明确不支持」表插在 Status 之后。发布走提案流程。

## 1. Run It Today（EN section）

```markdown
## Run It Today

```x
// examples/hello.x
static Int main() {
    print("hello, XNull")
    print("1 + 2 = " + str(1 + 2))
    return 0
}
```

```
$ go run ./cmd/xnull run examples/hello.x
hello, XNull
1 + 2 = 3
```

A tree-walking interpreter ships with the repository. It currently covers control flow, string interpolation, `try` propagation, and `defer`/`errdefer` (LIFO); unsupported features produce explicit diagnostics, never silent behavior. See `impl/README.md` for the exact scope, and the conformance ledger for item-by-item status.
```

## 2. 今天就能跑（中文部分）

```markdown
## 今天就能跑

```x
// examples/hello.x
static Int main() {
    print("hello, XNull")
    print("1 + 2 = " + str(1 + 2))
    return 0
}
```

```
$ go run ./cmd/xnull run examples/hello.x
hello, XNull
1 + 2 = 3
```

仓库自带 tree-walking 解释器。当前覆盖控制流、字符串插值、`try` 传播与 `defer`/`errdefer`（LIFO）；不支持的功能产生显式诊断，绝不静默。精确支持范围见 `impl/README.md`，逐项进度见一致性用例台账。
```

## 3. Design at a Glance / 设计速览（EN + CN）

```markdown
## Design at a Glance

| | XNull | Rust | Go |
|---|---|---|---|
| Memory strategy | Compiler-adjudicated (ARC/GC/stack), invisible in source | Ownership + borrow checker in source | GC only |
| Errors | `Result` values + `try` propagation + `defer`/`errdefer`; no exceptions | `Result` + panics | Values + panics |
| Polymorphism | Protocols only; no overriding | Traits (overriding allowed) | Interfaces |
| Accessors | None, not expressible | Common (getter methods) | None |
| Generics | Monomorphized, no constraints | Monomorphized + traits | Erasure |
```

```markdown
## 设计速览

| | XNull | Rust | Go |
|---|---|---|---|
| 内存策略 | 编译器判定（ARC/GC/栈），源码零注解 | 所有权+借用检查（源码表达） | 仅 GC |
| 错误 | `Result` 值 + `try` 传播 + `defer`/`errdefer`，无异常 | `Result` + panic | 值 + panic |
| 多态 | 只走协议，禁止覆写 | trait（可覆写） | 接口 |
| 访问器 | 语法层面不存在 | 常见（getter 方法） | 无 |
| 泛型 | 单态化、无约束 | 单态化 + trait | 擦除 |
```

## 4. Explicitly Unsupported / 明确不加（设计如此）

```markdown
## Explicitly Unsupported (by design)

| Feature | Reason |
|---|---|
| Method overriding | "Which method actually ran?" must be answerable from static types; dynamic dispatch exists only via protocols |
| Accessors / properties | Grammar-level separation: fields are data, behavior is verb-named methods |
| Reflection | Breaks the "source + spec determines everything" axiom |
| Exceptions | Errors are values: `Result` + `try`; `throw` is fatal-only and never unwinds |

The complete table with rationale is [S1 §0.6](./spec/XNull解决方案-第1部分-基础语法-v3.3.0.md).
```

```markdown
## 明确不加（设计如此）

| 特性 | 理由 |
|---|---|
| 方法覆写 | 「这个方法实际执行的是谁」必须看静态类型就能回答；动态分派只存在于协议 |
| 访问器 / 自定义属性 | 语法级分离：字段是数据，行为是动词命名的方法 |
| 反射 | 破坏「源码 + 规范决定一切」公理 |
| 异常 | 错误是值：`Result` + `try`；`throw` 仅致命 panic，不展开栈 |

完整表格及理由见 [S1 §0.6](./spec/XNull解决方案-第1部分-基础语法-v3.3.0.md)。
```

## 5. 状态行与结构更新（随本提案一并合入）

- Status 表：`Compiler (Go) | Frontend in progress (lexer / parser)` → `Runtime (Go) | Tree-walking interpreter live (3 examples run); C backend next`
- 仓库结构：`examples/ # Example programs (planned)` → `# Runnable examples (hello, Result/try, defer/errdefer)`
- Roadmap 第 1 条：标注解释器已上线，C 后端为下一里程碑
- 简介句：`early stages of a compiler implementation` → `an implementation you can run today`

## 6. 合入说明

- 技术表述已经回执-T3 确认（C2「and options」、C4「propagation/errdefer」、C6「判定表收紧」均已落实）。
- 输出为逐字节真实运行结果（2026-11-06 COO 实跑复核）。
- 发布动作走四道关：提案-002 → CEO 评审 → CTO 技术关（本稿已具 T3 背书，供其复核差异）→ CEO 终审 → 用户批准后 commit/push。
