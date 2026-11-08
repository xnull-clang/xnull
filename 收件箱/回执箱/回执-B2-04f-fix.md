# 回执：B2-04f-fix 解释器死循环（P0）

- **卡片**：B2-04f-fix（`TestS2BND08CrossPackageStatic` 60s 超时）
- **分支**：`pod/fix-interp`（未合 main）
- **代码提交**：`fa964d2`
- **结论**：**PASS**。根因不是 interp 派发递归，而是 `xparser.x` 的 factory 声明解析无进展循环；修复后目标用例 60s 内 PASS。

## 一、诊断

`XNULL_INTERP_TRACE=1` 轨迹显示调用深度稳定在个位/十几层，重复序列为：

```
Parser.parseTypeDecl → Parser.parseMember → Parser.parseType
```

不是 `callMethodFrom/dispatchCall/evalCall/execBlock` 的栈增长递归。

根因：`factory F for T {` 的 `{` 在 target 之后。`xparser.x` 只在 target 之前检查并消费 `{`；
target 解析完后 `{` 留在当前 token，成员循环 `while !self.at(13)` 每轮调用 `parseMember` 都不前进。

旧 `xparser.x` 在 factory 输入上 5s 未完成（`old-xparser-timeout.out`）；修复后同一输入 0.13s 输出 AST。

## 二、改动

| 文件 | 改动 |
| --- | --- |
| `impl/lib/b2/xparser.x` | factory/extension 分支在 target 解析后补 `if self.at(12) { self.next() }` |
| `impl/internal/interp/trace.go` | 新增 `XNULL_INTERP_TRACE`（默认关闭；`XNULL_INTERP_TRACE_LINES` 限行） |
| `impl/internal/interp/{interp,objects,statics,factory}.go` | 顶层函数/实例方法/静态方法/工厂方法接入轨迹 |
| `impl/internal/interp/b2_04f_test.go` | `TestXParserFactoryDeclTerminates`，15s 超时回归 |
| `tests/b2/parser_cases/factory.x` | factory 声明加入 L2 差分语料 |
| `evidence/B2-04f-fix/` | 原始输出与复跑说明 |

## 三、验证

| 项 | 结果 |
| --- | --- |
| 目标用例（默认 Go 前端） | PASS（2.17s） |
| 目标用例（`XNULL_FRONTEND=xnull` + 外部解释器） | PASS（2.18s） |
| `go test ./internal/interp` | PASS |
| `go test -p 4 ./internal/interp ./internal/frontbridge ./internal/codegen` | 3/3 PASS（codegen 263.7s） |
| `tests/b2/run-l2.sh` | PASS=43 FAIL=0 |
| `XNULL_INTERP_TRACE=1` 复跑 | rc=0，4122 行，max_depth=41，含 FactoryDecl |

## 四、边界

- 未恢复 `frontbridge.runInProcess`；B2-04f 的“默认 go + 外部进程硬超时”保持不变。
- 未改 `xlex.x`、`internal/xfront`。
- 只提交 `pod/fix-interp`。
