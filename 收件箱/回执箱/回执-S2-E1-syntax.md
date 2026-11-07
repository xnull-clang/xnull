# 回执：S2-E1-syntax（singleton / factory / extension / 注解）

- 角色：E1 前端组
- 工作树：`wt/e1-front`（分支 `pod/e1-front`）
- 日期：2026-11-07
- 范围：`impl/internal/xfront/**` 的 parser / AST / printer。**未写 codegen、未改 sema。**
- 结论：DONE。先红后绿，xfront 49/49 通过，下游 sema/codegen/interp/cli 不回归。

## 1. 交付内容

| 能力 | AST | 解析 | 打印 |
| --- | --- | --- | --- |
| `singleton Name { Member* }`（S2 §9） | `SingletonDecl` | `parseSingletonDecl` | `(singleton ...)` |
| `factory Name for Target { FactoryMember* }`（S2 §10） | `FactoryDecl` | `parseFactoryDecl` / `parseFactoryMember` | `(factory Name (for Target) ...)` |
| `extension Target { MethodDecl* }`（S2 §11） | `ExtensionDecl` | `parseExtensionDecl` / `parseExtensionMember` | `(extension Target ...)` |
| `@annotation Name { final Type f = expr; }`（S2 §12.1） | `AnnotationDecl` | `parseAnnotationDecl` | `(annotation ...)` |
| 注解使用（类型/字段/方法/构造器/deinit/参数/协议签名/枚举项） | `Annos` 字段 | `parseAnnotations` | `(@Name args...)` |
| `@Override` | 不特判，按普通注解使用解析 | 同上 | 同上 |

附带修正：

- `MethodDecl` 增加 `TypePars`，类方法与工厂方法支持方法级泛型参数（S2 §13）。
- `class/struct/singleton/enum` 成员解析合并为 `parseMember`，四处重复消除；类/结构体方法现在也支持 `<T>`。
- `PrintUnit` 原本不打印 `class/struct/protocol/enum`；本次一并补齐八类类型声明的 S 表达式。
- 删除 `dropSemiInAnnotation` 的全局扫描。该实现会在注解后的成员字段处继续吞分号（`@A Int x = 1` 的字段终止分号被误删）。改为在 `parseAnnotations` 内只消费注解行末的自动分号。
- `SYN-110` 不再产生，保留码值不复用（注释已更新）。

## 2. 先红

命令：

```bash
cd impl && go test -count=1 -run 'TestS2' ./internal/xfront/
```

原始输出：`evidence/E1-S2-red-2026-11-07.log`

关键失败：

```text
--- FAIL: TestS2Singleton
    不应有诊断：SYN-110 ... 类型声明（singleton）属第 2 部分 ...
--- FAIL: TestS2Factory
    期望顶层声明 ... 遇到 `factory`
--- FAIL: TestS2Extension
    不应有诊断：SYN-110 ... 类型声明（extension）...
--- FAIL: TestS2AnnotationDecl
    期望顶层声明 ... 遇到 `Marker`
--- FAIL: TestS2AnnotationUse
    期望类成员 ... 遇到 注解
FAIL	xnull.dev/xnull/internal/xfront
```

## 3. 后绿

命令：

```bash
cd impl && go vet ./internal/xfront/ && go test -count=1 -v ./internal/xfront/
```

原始输出：`evidence/E1-S2-green-2026-11-07.log`

```text
PASS
ok  	xnull.dev/xnull/internal/xfront	0.758s
```

- `=== RUN` 49，`--- PASS` 49，`--- FAIL` 0（原 44 + 新增 5）。
- 下游回归：

```text
ok  xnull.dev/xnull/internal/sema          0.833s
ok  xnull.dev/xnull/internal/codegen      18.621s
ok  xnull.dev/xnull/internal/codegen/ffi   8.596s
ok  xnull.dev/xnull/internal/interp        2.395s
ok  xnull.dev/xnull/internal/cli           6.781s
```

- `go build ./...` 通过。

## 4. 新增/调整测试

新增 `impl/internal/xfront/s2_syntax_test.go`：

- `TestS2Singleton`：字段/方法结构；`singleton X(Int a)` 拒绝。
- `TestS2Factory`：目标类型、`static` 工厂方法、方法级 `<T>`；缺 `static`、写 `final` 拒绝。
- `TestS2Extension`：目标类型 + 方法；写 `public` 拒绝。
- `TestS2AnnotationDecl`：两个 `final` 字段；非 `final` 字段、方法体拒绝。
- `TestS2AnnotationUse`：`@Marker("x")` 用于类型、`@Override` 用于方法、`@Marker` 用于字段、`@Deprecated` 用于枚举项。

调整 `TestUnitMultiDiags`：原用例依赖 `singleton` 产生 `SYN-110`，改为 `class { }` 触发 `SYN-101`，保留多诊断断言。

## 5. 边界与待办

1. 本卡只到语法/AST。`internal/sema` 对四类新声明目前是 `default: continue`（忽略），未做 §9.4/§10.5/§11.4/§12 的名称、目标类型、成员合法性检查；需单独开 sema 卡。
2. `internal/codegen` 对非 `TopFunc`/`ClassDecl` 顶层声明仍返回“未支持”；按本卡要求不动。
3. 文法与 §12.2 存在张力：S2 附录 A `ExtensionMember = MethodDecl` 未列注解，但 §12.2 允许“方法”带注解。实现选择接受扩展方法注解；如需严格按文法拒绝，改 `parseExtensionMember` 一行即可。
4. `factory` 方法的 `protected` 由文法接受、按 §10.2 应拒绝，留给语义层。
5. 未 push。
