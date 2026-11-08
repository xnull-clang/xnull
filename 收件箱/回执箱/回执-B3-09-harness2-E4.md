# 回执：B3-09 门禁脚本接 K-07 文件通道（E4）

- 前置：`git merge main`（含 `18d349f handoff/B3-K07-cli-contract.md`、E5 `xdk.sys.readFileText`）。
- 结论：默认改走 K-07 文件形态；当前 xnullc 未实现新 flag，门禁以 `--inline-args` 保持可跑。
- 只改 `tests/b3/`，未改 xnullc / Go oracle。

## 改动

1. `tests/b3/xnullc_all.py`
   - 默认文件形态：AST 写 `<tmp>/ast.txt`，bundle 写 `<tmp>/bundle.json`（所有入口都落盘），
     调 `xnullc <entry> --ast-file <p> --project <text> [--bundle-file <p>]`；
     多文件入口才追加 `--bundle-file`。
   - 新增 `--inline-args`：回退合同 1.1 位置参数。
   - 新增 `supports_file_args()` 预检：xnullc 源内无 `--ast-file` 且未加
     `--inline-args` 时退出 2，并在 stderr 说明。
   - 文件写入失败 / AST 或 bundle > 16 MiB → `status=K07-LIMIT`、`cause=K-07-LIMIT`；
     xnullc 非 0 且诊断含文件路径、`readFile`、`No such file` 等也归 K07-LIMIT。
   - 删除 `ARGMAX` 分支；`Argument list too long` 统一归 K07-LIMIT。
   - 执行失败保留临时目录，note 追加 `tmp=<dir>`；成功即 `shutil.rmtree`。
2. `tests/b3/xnullc-all.sh`：用法补 `--inline-args` 与文件形态说明（参数原样透传）。
3. `tests/b3/README.md`：文件形态/兼容形态/16 MiB/当前 xnullc 缺口与运行命令。
4. `tests/b3/test_xnullc_all.py`：K-07 单测 7 条（超限、写入失败、缺失文件、路径命中、
   E2BIG、普通解析错误不误判）。

## 先红后绿

- 红：`tests/b3/evidence/harness2-red.log` —— 默认形态对当前 xnullc 退出 2：
  `xnullc 尚未实现 --ast-file/--bundle-file/--project（K-07 合同 1.2）`。
- 绿：`tests/b3/evidence/harness2-green.log` + `harness2-out/results.tsv` ——
  `--inline-args` 全量 241 文件：
  `raw 0 diff 84；status {NEG-PASS:98, DIFF:56, PASS0:84, K07-LIMIT:1, FAIL:2}`。
  - `impl/lib/b2/xparser.x` 由原 `ARGMAX` 改为 `K07-LIMIT`（E2BIG），不再出现 ARGMAX。
  - 2 条 FAIL 为合并后语料的 Go emit-c 失败（`t00_sanity_text` 走 `xdk.sys` 新 API，
    E5/E2 尚未收敛），与脚本通道无关；非本卡引入。
- 单测：`cd tests/b3 && python3 -m unittest test_xnullc_all` → 7/7 OK。

## 用法

```bash
# 现态（xnullc 未实现新 flag）
tests/b3/xnullc-all.sh --inline-args --all-shards 4 --parallel 8

# E2 合入文件通道后（默认）
tests/b3/xnullc-all.sh --all-shards 4 --parallel 8
```
