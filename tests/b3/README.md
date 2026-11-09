# B3 测试脚本（E4）

本目录的门禁脚本只读 Go oracle 与 xnullc，不修改生成器本身。

## B3-09 全量门禁

```bash
# 默认：文件形态——AST/bundle 先写临时文件，再调 xnullc
tests/b3/xnullc-all.sh --shard 1/1 --parallel 8

# 强制重建默认二进制（当前 HEAD）
tests/b3/xnullc-all.sh --rebuild --shard 1/1 --parallel 8

# 跑全部分片并聚合（任一 shard 红则整体红；分片前统一构建一次）
tests/b3/xnullc-all.sh --all-shards 4 --parallel 8

# 聚合已有 shard
tests/b3/xnullc-all.sh --aggregate

# 兼容旧位置参数形态（K-07 合同 1.1）
tests/b3/xnullc-all.sh --inline-args --shard 1/1 --parallel 8
```

Go helper 可用环境变量 `XNULL_BIN` / `XNAST_BIN` 或 `--go-bin` / `--xnast-bin` 指定。

**二进制新鲜度（门禁硬规则）**：`xnullc-all.sh` 默认使用带 git HEAD 短 SHA 的版本化二进制路径
（`/tmp/xnull-b3-all-<HEAD>`、`/tmp/xnast-b3-all-<HEAD>`），不存在才构建；`--rebuild` 强制重建。
`--all-shards` 在全部分片前构建一次，并把同一对二进制路径传给每个 shard 与 aggregate。
门禁**不得复用无版本的旧 `/tmp` 二进制**；显式传入 `--go-bin/--xnast-bin` 或设置
`XNULL_BIN/XNAST_BIN` 时，由调用方保证二进制与当前 main/工作树一致。

**超时与长用例**：`xnullc_all.py` 的子进程超时默认 **900s**（`--timeout` 可调）；xnullc 生成步骤显式使用该超时。`LONG_CASES`（当前含 `impl/lib/b2/xparser.x`）在 shard 内串行执行（低并发），避免高并发资源竞争导致假超时。

### K-07 文件通道（`handoff/B3-K07-cli-contract.md`）

- 默认形态（合同 1.2）：

  ```bash
  xnullc <entry.x> --ast-file <ast.path> --project '<projection>' \
    [--bundle-file <bundle.path>]
  ```

  AST 与 bundle 均写入 `tempfile.mkdtemp(prefix="b3-09-")`；bundle 对所有入口都落盘，
  多文件入口额外传 `--bundle-file`。成功用例结束即删除临时目录。
- 兼容形态（合同 1.1）：`--inline-args` 时仍用位置参数
  `xnullc <entry.x> '<ast>' '<projection>' ['<bundle>']`。
- 文件写入失败或 AST/bundle 超过 16 MiB：记 `status=K07-LIMIT`、`cause=K-07-LIMIT`，
  note 写明路径与原因；不会再产生 `ARGMAX`。
- xnullc 以非 0 退出时，若错误信息包含文件路径或读取类诊断（`readFile`/`读取`/
  `No such file` 等），同样归 `K07-LIMIT`。
- 执行失败保留临时目录，路径写入 `results.tsv` 的 `note`（`tmp=...`），便于复盘。

### 当前 xnullc 实现状态

`impl/lib/b3/xnullc.x` 尚未实现 `--ast-file` / `--bundle-file` / `--project`，
默认文件形态会失败。在 E2 完成新 flag 之前，门禁需显式加 `--inline-args` 保持绿：

```bash
tests/b3/xnullc-all.sh --inline-args --all-shards 4 --parallel 8
```

E2 合入文件形态后，去掉 `--inline-args` 即可切回默认通道。

## 其它脚本

`run.sh`、`emit-diff.sh`、`dual-path.sh`、`negative.sh`、`ast-bundle.sh` 及
`xnullc-*.sh` 为 B3 各卡的定点回归；`xnullc_all.py` 为全量门禁实现。
