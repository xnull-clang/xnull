# 回执：B3-09 全量门禁脚本（E4）

- 结论：新增 `tests/b3/xnullc-all.sh` + `xnullc_all.py`，只读基线，不改 xnullc/oracle。
- 红：`evidence/B3-09-harness/red.log`（xnullc 路径缺失 → 退出 2）。
- 绿：`evidence/B3-09-harness/green.log`（全量 241 文件跑通，结果复现基线）。

## 能力

1. 读取 `handoff/B3-09-baseline.tsv`（缺失时回退 `git ls-files` 并自动区分负例）。
2. 单文件：`--ast` + project；多文件：追加 `--emit-ast-bundle` JSON。
3. 每项记录 raw unified diff 行数与归一化（`xn_tN→xn_t#`、去前导缩进）content diff。
4. 负例：只跑 Go emit-c，非零退出记 `NEG-PASS`；记录 Go 退出码/首条诊断。
5. `--shard k/n`：`sha256(path)` 前 16 hex 取模，确定性；`--parallel N` 并发；
   `--all-shards N` 跑全部 shard 后 `--aggregate`；任一非 `PASS0/NEG-PASS` 整体红。
6. 输出 `results.tsv`（path/group/kind/files/shard/go_exit/raw/content/status/cause/note）
   与汇总（raw 0 diff/总数、状态分布、首因计数、前 20 条 RED）。

## 全量结果（当前基线）

`241 文件；raw 0 diff 83；status {NEG-PASS:98, DIFF:59, PASS0:83, ARGMAX:1}`；
首因：K-06 temp/编号/缩进 21、K-06 temp/root 17、K-02 容器 typedef 10、
K-05 Result typedef 7、K-01 void 3、K-04 非 ASCII 1、K-07 argv 上限 1。
退出 1（按“任一失败整体红”口径，符合当前基线）。

分片验证：`--shard 2/2` 选中 123 文件，与 1/2 的 118 合计 241。

## 用法

```bash
tests/b3/xnullc-all.sh --shard 1/1 --parallel 4
tests/b3/xnullc-all.sh --all-shards 4 --parallel 4
tests/b3/xnullc-all.sh --aggregate
```
（Go helper 可用 `XNULL_BIN`/`XNAST_BIN` 或 `--go-bin/--xnast-bin` 指定。）
