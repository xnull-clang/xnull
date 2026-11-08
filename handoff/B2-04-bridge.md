# B2-04 桥接设计：Go CLI → XNull 前端

> 状态：定稿（B2-04）。范围：`impl/internal/frontbridge`（新包）、`impl/internal/cli`、`impl/internal/codegen`、`impl/internal/xdkcheck` 的解析入口。
> 约束：`impl/internal/xfront` 只读；不改 `impl/lib/b2/xlex.x`、`xparser.x` 语义；不做 xfront 反向写回。

## 1. 目标与调用链

`xnull check/run/build` 的解析入口（目前共 4 处）统一改为：

```
cli/run/check/build
  └─ codegen.LoadUnits / cli.policyFile / xdkcheck
       └─ frontbridge.ParseUnit(file, src)
            ├─ 1. Go xfront.ParseUnit  → 仅作 oracle：错误诊断 + 回退 AST
            └─ 2. XNull 前端（xparser.x）→ 正常路径的唯一 AST 来源
                 └─ xnast v1 S 表达式 → frontbridge 反序列化 → *xfront.CompilationUnit
```

`sema`、`interp`、`codegen` 继续消费 `*xfront.CompilationUnit`，其字段类型不变，因此下游零改动。

## 2. 序列化契约

沿用 B2-00 冻结的 `xnast v1`（`tests/b2/FORMAT-v1.md`）：

- 节点：`(TypeName (Field Value) ...)`，导出字段全量、声明顺序。
- 切片：`(slice v1 v2 ...)` / `(slice)`；空值：`(nil)`。
- 标量：字符串按 `strconv.Quote`，布尔 `true/false`，整数十进制；`Pos` 为 `(Pos (Line n) (Col n))`。
- 位置口径、`(depth-limit)` 截断均由 B2-03 的 `xparser.x` 产出，桥接不重算。

桥接只做**反序列化**：词法/语法/位置/depth-limit 的权威定义在 `xparser.x`，避免双份逻辑漂移。

## 3. 反序列化

`internal/frontbridge/deserialize.go` 实现：

1. 轻量 S 表达式解析器（不依赖 map 迭代，保持确定性）。
2. 反射解码：按目标 Go 类型递归解码 struct/pointer/slice/interface/标量。
3. 具体类型注册表：接口字段（`Expr`/`Stmt`/`TypeRef`/`TopDecl`）按打印类型名查表，并校验实现关系。
4. 解码后可用 `xfront.PrintUnitPos` 重打印；与输入 dump 逐字节一致作为自检门禁。

## 4. 运行方式与失败回退

XNull 前端有两种执行器，按优先级选择：

| 执行器 | 条件 | 说明 |
|---|---|---|
| 外部自举二进制 | `XNULL_SELFHOST_BIN` 可执行 | `"$BIN" run --interp <xparser.x> <src>`；本地/CI 可指向带完整 interp 的构建 |
| 进程内解释器 | 外部未配置且 `internal/interp` 能运行 xparser | `interp.Run(xparserAST, out, args)`；主分支具备 Bytes 后自动启用 |
| Go oracle | 以上失败或 `XNULL_FRONTEND=go` | 直接返回 `xfront.ParseUnit` 结果 |

回退矩阵：

| `XNULL_FRONTEND` | 正常 | XNull 失败/超时 | 诊断非空 |
|---|---|---|---|
| `auto`（默认） | 用 XNull AST | 回退 Go AST，不报错 | 返回 Go 诊断（消息/位置完全保真） |
| `xnull` | 用 XNull AST | 返回桥接失败诊断（不静默） | 返回 Go 诊断 |
| `go` | 不用 XNull | — | Go 诊断 |

说明：Go oracle 在入口处先跑一次，只用于“诊断与回退”；正常文件的 AST 来自 XNull。这样 `check` 的错误消息、退出码、诊断顺序与旧路径逐字节不变。

超时：外部执行器默认 120s（`XNULL_SELFHOST_TIMEOUT` 秒级覆盖）；超时按失败回退。
递归保护：外部执行器启动时注入 `XNULL_FRONTEND_INNER=1`，子进程内层解析直接走 Go oracle，避免自举前端递归拉起自身。
性能护栏：`auto` 模式对单文件源码 >16KB 直接回退 Go（`XNULL_FRONTEND_MAX_BYTES` 可调）；`xnull` 模式不受限。进程内执行器首次使用前做一次 `Bytes` 能力探测，失败后按进程缓存，不再逐文件重试。

## 5. 缓存与性能

- 进程内缓存：`sha256(parser 版本 + 源码)` → XNull AST dump，避免同一进程重复解析（XDK 多文件、多文件工程）。
- 只缓存成功输出；失败不缓存，便于修复后立即重试。
- 大文件（如 `impl/xnfmt/xnfmt.x`）在解释器下较慢，属已知基线；`auto` 在超过大小阈值或超时后回退，不阻塞工具链。
- `(depth-limit)`：dumpReflect 的 64 层截断会丢深层子树，桥接视为传输失败并回退 Go oracle（`auto`），保证 AST 完整。

## 6. 差分与 CI

- `internal/frontbridge/diff_test.go`（Go 测试内差分器）：
  - L1：`xlex.x` token dump ↔ `xfront.PrintTokens`；
  - L2：`xparser.x` AST → 反序列化 → `PrintUnitPos` ↔ oracle；
  - L3：`xparser.x --diags` 的 `(code,line,col)` 序列 ↔ oracle。
- 默认 `go test ./...` 只跑轻量自检（反序列化往返、回退路径）；全语料差分需显式 `XNULL_B2_DIFF=1`，并设置 `XNULL_SELFHOST_BIN`（或 `XNULL_BIN`），避免默认 CI 120s 超时。
- `ci/run.sh` 第 04 项：检测到可执行的自举二进制时运行该差分，否则显式 SKIP（不伪装 PASS）。
- 主分支 interp 具备 Bytes 后，差分器自动走进程内执行器，无需外部二进制（仍建议显式开启 `XNULL_B2_DIFF=1` 控制耗时）。

## 7. 回滚

- 环境开关 `XNULL_FRONTEND=go` 可立即恢复旧解析路径（无需回滚代码）。
- 删除/停用 `frontbridge.ParseUnit` 的 XNull 分支即回到 B2-03 前状态；下游无感知。
