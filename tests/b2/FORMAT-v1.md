# B2 oracle 格式 v1（冻结）

> 冻结日期：2026-11-08　适用：B2-00 起的 Go/XNull 前端差分
> 工具：`impl/cmd/xnast`；库入口：`xfront.PrintTokens`/`PrintUnitPos`/`PrintDiags`
> 语料清单：`tests/b2/corpus.tsv`（sha256 + 路径，按路径升序）

## 1. 三层输出

| 层 | 命令 | 输出头 | 内容 |
|---|---|---|---|
| token | `xnast --tokens file.x` | `xnast-tokens v1` | 一行一个 `Token`，含全部字段与位置 |
| AST | `xnast --ast file.x` | `(xnast v1 ...)` | 反射式全字段 AST，含每个节点位置 |
| 诊断 | `xnast --diags file.x` | `xnast-diags v1` | 一行一个 `diag.Diagnostic`，含全部字段 |

数据输出即使存在语法/词法诊断也写 stdout 并退出 0；文件不可读退出 2。
诊断不是“失败退出”，而是被比较的数据。

## 2. 语法（规范化文本）

### 2.1 通用值

```
(nil)                         空指针/空接口
(TYPE (FIELD VALUE) ...)      结构体：TYPE 为 Go 类型名，字段按声明顺序、全字段
(slice VALUE ...)             切片；nil 为 (slice)
"..."                         字符串，Go %q 转义
true / false
42                            有符号/无符号整数、rune 均按十进制
1.5                           浮点
```

- 每个 AST 节点都带 `P (Pos (Line N) (Col M))`；位置 1 基、列按 Unicode 标量。
- 字段名来自 Go 结构体字段名；未导出字段不输出。
- 不使用 map 迭代；AST 中没有 map 字段。
- 输出 UTF-8 + LF；AST 单行，token/诊断一行一项。

### 2.2 token

每行形如：

```
(Token (Kind 2) (Text "package") (Pos (Pos (Line 1) (Col 1))) (Str 0) (Value "") (Segs (slice)) (Interps (slice)) (Char 0) (Base 10) (Suffix "") (HasSuffixF false))
```

`Kind` 数值与 `xfront.Kind` 常量一致；`Str` 为 `StrKind` 数值。所有字段即使用默认值也输出，避免“字段被省略导致假一致”。

### 2.3 AST

形如：

```
(xnast v1 (CompilationUnit
  (P (Pos (Line 1) (Col 1)))
  (Package (nil))
  (Imports (slice))
  (Decls (slice
    (TopFunc (P (Pos (Line 1) (Col 1))) ... (Name "main") ...)))))
```

- `PrintUnitPos` 只输出 AST；不含源文本、文件名、时间。
- 与既有 `PrintUnit` 的关系：`PrintUnit` 保留为人读摘要（不含位置），B2 比较使用 `PrintUnitPos`。

## 3. 比较规则

1. 同一文件分别取 Go/XNull 的同层输出，`bytes.Equal` 为 PASS。
2. 同一实现连续两次输出必须字节相等（DET-01）。
3. 先比 L1 token，再比 L2 AST，最后比 L3 诊断；L2 通过才可作为 B2 硬指标。
4. 失败证据：`evidence/B2/<case>/{go.out,xnull.out,diff}`；不得只截取“看起来一样”的行。
5. 语料路径与 SHA-256 以 `corpus.tsv` 为准；新增/修改语料先更新清单。

## 4. 版本与边界

- 本文件冻结 **v1**；格式变更需新版本（v2）与全量语料重基线，不得静默改 v1。
- 位置当前为 `line:col`，不包含字节偏移；若后续需要 `@off`，走 v2。
- 诊断消息模板先随实现冻结；模板变更需同步更新期望与证据。
- 语料 v1 为当前分支可读文件；main 合入 8 个 XDK 单元后，B2-01 刷新 `corpus.tsv`（仅加路径/哈希，不改格式）。
