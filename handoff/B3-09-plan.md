# B3-09 执行计划（v1.0.0）

> 依据：`收件箱/门/B3-09范围-v1.0.0.md`（验收冻结）、`handoff/B3-09-baseline.md`、
> `handoff/B3-k06-clusters.md`、`handoff/B3-typedef-void-spec.md`、
> `handoff/B3-K07-cli-contract.md`。单写者：E2（`impl/lib/b3/xnullc.x`）；
> E4 维护门禁脚本；E5 维护 runtime/`xdk.sys`。

## 顺序与卡

| 卡 | 范围 | 目标 | 验证 |
|---|---|---|---|
| B3-09-01 | K-01 `void` 签名/定义 | parser-seed 等 11 文件 | 目标文件 0 diff；harness 分片 |
| B3-09-02 | K-09 空参数 / K-10 私有字段 / K-11 Result 零值 | 15+2+8 文件中的小差异 | 各代表 0 diff |
| B3-09-03 | K-02 容器 typedef（arr/set/map） | classes、f2、bundle/app 等 14 | 代表 0 diff + 顺序 |
| B3-09-04 | K-03 函数指针 typedef `xn_fn_*` | collections_basic/nonnull | 0 diff |
| B3-09-05 | K-05 Result 错误类型 typedef | sync_basic、result-try | 0 diff |
| B3-09-06 | K-04 非 ASCII 字符串 | bundle_text、a01_member_visibility 等 8 | 中文原样进 `rt_string_from_c` |
| B3-09-07 | K-08 Bytes 临时释放顺序 | t04_bytes_surface | 0 diff |
| B3-09-08 | K-06 长尾（xlex/xnfmt/lexer-seed 等） | 40 root + 31 defer + 12 while + 4 blockHeld | 逐文件 0；通用规则，不按函数特判 |
| B3-09-09 | K-07 文件通道接入 xnullc | xparser.x 不再 ARGMAX | 合同 §4 四项 |
| B3-09-10 | 全量门禁 | 143 入口 0 raw；98 负例；确定性；双路径 9/9 | `xnullc-all.sh --all-shards 8` |
| B3-09-11 | 证据与门报告 | `evidence/B3-09/` 六件套 | 董事会判定 |

## 规则

1. 每卡只跑目标 fixture + 一个 harness 分片；不串行全量。
2. 修改 `xnullc.x` 后必须重跑上一卡的代表文件，防止回退；回退即本卡红。
3. K-06 只允许改通用发射器；函数级特判仅限已冻结的 regexMatchAt 参考路径，
   且 B3-09-08 结束前必须移除。
4. 每卡 30 分钟无进展必须提交中间版本并说明剩余。
5. 全量门禁只在 B3-09-10 跑；任何中间卡不得声称 B3-09 通过。

## 当前基线（2026-11-09 05:55 快照）

- 241 文件；入口 143；负例 98；PASS0 84；DIFF 58；ARGMAX 1。
- text `bundle_text` raw 349（B3-08 内），不在 B3-09 范围重复计。
