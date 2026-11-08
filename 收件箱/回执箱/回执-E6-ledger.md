# 回执：E6-ledger（台账锚点正则修复）

| 字段 | 内容 |
|---|---|
| 卡片ID | E6-ledger（`TestBuildLedgerRepoGoldenScale` 红：101/74 vs 103/75） |
| 角色/会话 | E6（自举线执行位），工作树 `wt/e6-toolchain`，分支 `pod/e6-toolchain` |
| 结论 | **DONE**（pod 已修，待 owner 合并 main） |
| 改动 | `impl/internal/devtool/ledger.go`：`ledgerRowRe` 前缀 `[A-Z]{2,6}` → `[A-Z]{2,10}`（补 7 字母 `TIMEOUT`/`FACTORY`）；`impl/internal/devtool/ledger_test.go`：`goldenLedgerRows` 101 → 103；`goldenLedgerPass` 保持 75（TIMEOUT-01 在 status.tsv 为 PASS，FACTORY-01 未登记 → 未实现）。未改其他用例、未改状态表数据。 |
| 验证（命令+结果） | `cd impl && go test ./internal/devtool -count=1` → **ok**（3.6s）。生成台账实测：**103 行**；`FACTORY-01` 第 55 行（S2，**未实现**）；`TIMEOUT-01` 第 81 行（S4，**PASS**）；表头 `总计 103 条（PASS 75）`；按文档 `S1 14 · S2 30 · S3 11 · S4 11 · S5 9 · S6 10 · S7 7 · S8 11`；按里程碑 `M0/M3 11 · M1 20 · M2 50 · M3 22`。 |
| sha | **`4a3a223`**（pod/e6-toolchain；`fix(devtool): ledger anchor regex accepts 2-10 letter prefixes`）；基线 `8468909` |
| 证据路径 | 复现：`cd impl && go test ./internal/devtool -count=1`；台账：`go build -o /tmp/xnull ./cmd/xnull && /tmp/xnull dev ledger`（生成后核对并还原工作树文件） |
| 未测/风险 | ①main 仍红，需合并本提交后 `internal/devtool` 方转绿；②`FACTORY-01` 在 status.tsv 无登记，台账显示「未实现」——若 S2 工厂类型已验收，需另行补 status 行（本卡只修解析器，不改状态数据）；③`FACTORY-01` 前缀无里程碑映射，按默认落 M3（既有规则，未改）。 |
| 下一步 | E4 合并 pod→main；若 `FACTORY-01` 已有验收证据，由 S2 owner 补 `status.tsv` 行后重跑 `dev ledger`。 |
是否越界：否
