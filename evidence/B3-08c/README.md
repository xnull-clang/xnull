# B3-08c 证据：xnullc 消费 AST bundle（PARTIAL）

## 结论

- xnullc 接受 `xnast-bundle v1`（入口 + import 闭包，依赖后序）：
  - 解析 bundle JSON 的 `files[].ast`，按顺序合并各单元 `Decls`；
  - 合并后直接走既有发射器（入口 `path` 用作 `#line`，与 Go `--emit-c` 同口径）；
  - 与第三次参数（FFI 注册表投影）可同时使用。
- 多文件锚点：
  - `bundle_sync`、`bundle_tasks`、`bundle_collections`：C 与 Go `--emit-c` 逐字节一致，双路径通过；
  - `bundle_text`：仍 DIFF（既有的 String/Text/Bytes/`List<UInt16>`/Result 发射面缺口，非 bundle 合并问题）。

## 验收

```text
PASS bundle_sync
PASS bundle_tasks
PASS bundle_collections
KNOWN-DIFF bundle_text (3460 lines; String/Text/Bytes emission gap)
xnullc-bundle 汇总：PASS=3 FAIL=0 (text=KNOWN-DIFF)
```

- 先红：空 stub 全红（`red.out`）；绿 3/3（`green.out`）。
- `hashes.out`：sync/tasks/collections 三例 Go/XNull C SHA-256 相同且两次生成相同；text 稳定但 DIFF。
- 双路径：三例 Go C 与 xnullc C 同 cc/运行时编译运行，stdout/退出码一致。
- `bash tests/b3/run.sh` 全绿（含 B3-00..08c 既有卡片；text 记 KNOWN-DIFF）。

## 未完成 / 阻塞

- `bundle_text` 需补齐 XDK text 源码面依赖：
  - String 成员（`length/substring/indexOf/...`）与字符串相等按 `xn_str_*` 发射；
  - `Bytes` 成员（`xrt_bytes_*`）、`Text`/`Format`/`Regex` 成员；
  - `Result<T, Error>` 构造/Err 路径与 `List<UInt16>` 的完整发射细节；
  - 类方法/顶层函数 temp 分配顺序与 Go 对齐。
- 这些属既有 B3-02/04 语言面缺口，不是 bundle 合并格式问题；建议作为 B3-09 全量收口的输入。
- 未改 Go oracle/bundle 格式、未改 `xparser.x` 语义。

## 边界

- bundle JSON 由 B3-08b 的 `xnull --emit-ast-bundle` 生成并作为测试快照提交；路径字段不参与发射。
