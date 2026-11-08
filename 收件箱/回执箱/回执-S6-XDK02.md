# 回执：S6-XDK-02 静态核验

- **状态**：`DONE`（Go 测试内建，无独立脚本体系）
- **依赖矩阵**：`impl/docs/xdk-packages.tsv` 为 SSOT；`CheckXDKContracts` 校验实际 `xdk.*` import 在允许集内、无环；`errors→runtime`、`text→errors` 等规则显式登记；既有 `TestXdkPackageSkeletons` 矩阵同步修正（含缺单元跳过）。
- **稳定性/命名**：8 包表与磁盘单元一一对应；类型 PascalCase、函数/方法/字段 lowerCamel、枚举项 PascalCase、布尔读 `is/has`、私有 `_name`；源码头稳定性标记与表一致（表缺失/非法/冲突均报）。
- **资源/无隐式**：每个 `.xfb` handle 必须有存在的 close 入口；XDK 类持句柄字段必须有 `close()`；顶层非 final/const 字段、singleton 可变字段、隐式 init/cleanup/threadLocal 注解均拒绝。
- **测试**：`xdk_contract_test.go` 夹具覆盖每条规则正反例；`TestXDKContractsRepo` 在 8 单元齐备时跑真仓库（本分支缺 E3 单元时跳过）；已用 main 快照 `XNULL_XDK_REPO` 预检通过。
- **证据**：`evidence/S6-XDK02/`（红→绿、`go test ./...`、main 快照）；四包+cli 全绿。`go test ./...` 仍有既有红：`Tests` SYN-110、`devtool` 台账 golden，与本卡无关。
- **合并注意**：`impl/internal/codegen/xdk_skeleton_test.go` 在 main 已有同名文件；本卡修正了其依赖矩阵（`text→errors` 等）并加“缺单元跳过”。合并冲突时请保留本卡口径，或改为直接调用 `CheckXDKContracts`。
