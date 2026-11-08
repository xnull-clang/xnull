# B3-01 证据：xnullc 骨架

## 结论

- 新增 `impl/lib/b3/xnullc.x`：XNull 版入口（`<entryPath> <xnast-v1-ast>`）、显式 `EM`（Emitter）与 `SC`（Scope）状态、固定 prelude、空程序/hello 发射。
- 验收：空 `main` 与 `hello.x` 的 C 文本与 Go `xnull build --emit-c` **逐字节一致**（`green.out`）。
- 先红：用空 stub 替换 xnullc，脚本 `PASS=0 FAIL=2`（`red.out`）。

## 运行方式

B3-01 骨架从 **B2 前端 AST** 出发（`xnast --ast` 或 XNull 前端），C 文本由 xnullc 发射；
执行方式为 `xnull run --interp impl/lib/b3/xnullc.x -- <entryPath> <ast>`。
prelude 是 Go oracle 当前冻结输出（B3-01 仅覆盖空 main/hello 所需的最小面）。

## 测试

```bash
bash tests/b3/xnullc-skeleton.sh
# PASS skel tests/b3/fixtures/empty_main.x
# PASS skel examples/hello.x
# xnullc-skeleton 汇总：PASS=2 FAIL=0
```

`tests/b3/run.sh` 已接入该脚本；`xnull check impl/lib/b3/xnullc.x` 通过（`check.out`）。
`hashes.out` 记录两例 Go/XNull C 的 SHA-256（相同）。

## 边界

- 只新增 `impl/lib/b3/`、`tests/b3/`。
- 未改 Go codegen / oracle，未改 xparser.x 语义。
