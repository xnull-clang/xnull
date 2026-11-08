# B2-04f-fix 证据：factory 声明在 xparser.x 中的无进展循环

## 结论

`TestS2BND08CrossPackageStatic` 超时的根因**不在 `impl/internal/interp` 的派发/递归**，而在
`impl/lib/b2/xparser.x` 的 `parseTypeDecl`：`factory F for T {` 的 `{` 位于 target 之后，
旧代码只在 target 之前执行 `if self.at(12) { self.next() }`，target 解析完后 `{` 无人消费，
成员循环 `while !self.at(13) { parseMember(...) }` 原地打转。

解释器栈里的 `callMethodFrom → dispatchCall → evalCall → execBlock` 是**循环体内的调用链**，
不是栈增长型递归；`XNULL_INTERP_TRACE=1` 显示深度稳定在个位/十几层，调用序列重复的是
`Parser.parseTypeDecl → Parser.parseMember → Parser.parseType`。

## 修复

- `impl/lib/b2/xparser.x`：factory/extension 分支在 target 解析后补消费 `{`。
- `impl/internal/interp`：新增 `XNULL_INTERP_TRACE` 调用轨迹（默认关闭、零开销），
  用于后续同类问题的定位；新增带 15s 超时的回归用例 `TestXParserFactoryDeclTerminates`。
- `tests/b2/parser_cases/factory.x`：加入 L2 差分语料，L2/L3 43/43 PASS。

## 复现与验证

```bash
cd impl
# 默认路径（Go 前端）
go test ./internal/codegen -run TestS2BND08CrossPackageStatic -count=1 -v -timeout 60s
# 显式 xnull 前端 + 外部解释器
XNULL_FRONTEND=xnull XNULL_SELFHOST_BIN=/tmp/xnull-fixed \
  go test ./internal/codegen -run TestS2BND08CrossPackageStatic -count=1 -v -timeout 60s
# 回归用例
go test ./internal/interp -run TestXParserFactoryDeclTerminates -count=1 -v -timeout 60s
# 轨迹
XNULL_INTERP_TRACE=1 XNULL_INTERP_TRACE_LINES=100000 \
  /tmp/xnull-fixed run --interp lib/b2/xparser.x -- "$(cat /tmp/fac.x)"
```

| 文件 | 内容 |
| --- | --- |
| `repro-default.out` | 目标用例默认路径 PASS |
| `repro-xnull.out` | 目标用例 `XNULL_FRONTEND=xnull` PASS |
| `interp-trace.out` | 新 xparser.x 轨迹：rc=0，4122 行，max_depth=41，输出含 FactoryDecl |
| `old-xparser-timeout.out` | 旧 xparser.x：5s 超时，轨迹重复 `parseTypeDecl/parseMember/parseType` |
| `xparser-factory.ast` | 修复后 factory 输入的 AST dump |
| `l2.out` | `tests/b2/run-l2.sh`：PASS=43 FAIL=0 |

## 边界

- 未恢复 `frontbridge.runInProcess`；B2-04f 的“默认 go + 外部进程硬超时”保持不变。
- 未改 `xlex.x`，未改 `internal/xfront`。
