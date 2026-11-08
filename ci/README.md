# ci/ — XNull CI 唯一入口

```bash
bash ci/run.sh              # 顺序执行 11 项
bash ci/run.sh --list       # 只列 11 项
bash ci/run.sh --only 11    # 只跑第 11 项
```

退出码：全部 PASS=0；任一 FAIL=1；无 PASS 且只有 SKIP=2；用法错误=64。

## 十一项

| # | 名称 | 状态 | 说明 |
|---|---|---|---|
| 01 | gofmt+vet | 真实现 | `gofmt -l` 必须为空；`go vet ./...` |
| 02 | go test | 真实现 | `go test -timeout 120s ./...` |
| 03 | C 运行时构建 | 真实现 | `impl/runtime/build_rt.sh` |
| 04 | B2 双路径差分 | 条件实现 | 设置可执行的 `XNULL_SELFHOST_BIN`/`XNULL_BIN` 时跑全语料三层差分；未设置显式 SKIP |
| 05 | check_specs 六检 | SKIP 桩 | 同上 |
| 06 | 台账再生成 diff | SKIP 桩 | 同上 |
| 07 | 泄漏扫描 | SKIP 桩 | 同上 |
| 08 | 产物与 sha | SKIP 桩 | 同上 |
| 09 | 汇总 JSON | SKIP 桩 | 同上 |
| 10 | 文件名扫描（禁旧扩展名） | 真实现 | 仓库根递归无旧扩展名文件（点 + x + n；排除 `.git`、`wt/`、`xnull/`）；活引用执行 `git grep` 同一后缀的正则，排除 `日志/`、`收件箱/`、`evidence/` 后为 0 |
| 11 | xnfmt 全仓校验 | 真实现 | 每个 `.x` 格式化两次结果相同（幂等全仓强制）；未格式化文件必须在 `ci/xnfmt-baseline.txt`（存量冻结，只减不增），新增未格式化文件即 FAIL；baseline 中已规范文件只提示移除 |

## 第 10 项

依据董事会令 S1-22 第 3 条第 1、3 项。扩展名已统一为 `.x`；历史记录（日志/收件箱/evidence）豁免。命中任一条件即 FAIL，并在日志中列出命中文件/行。

## 产物

运行日志在 `ci/.out/`（`.gitignore` 全忽略，不入库）：每步 `step-NN.log`，汇总 `steps.jsonl`。
