# B4b/B4c 计划（2026-11-11）

> 依据：`handoff/B3-10-go-inventory.md`、ADR-001/009。
> B4a 已 PASS（xn-s2==s3==s4，9 示例 native 9/9）。

## B4b：XNull CLI/devtool 接管（约 40 文件 / 10k 行）

### 目标

在保留 Go oracle 的前提下，用 XNull 实现的 CLI 接管工程工具链，使 B4c 可以删除
Go CLI/devtool 而不影响构建、测试、打包。

### 卡

| 卡 | 范围 | 验收 |
|---|---|---|
| B4b-01 | CLI 引导：参数解析、`build`/`run` 调用 xnullc + xparser/xlex，`--emit-c`/`--ast-file`/bundle | hello + 9 示例 |
| B4b-02 | `dev test`：分片/并行、聚合、缓存、超时 | 与 Go `dev test` 结果一致 |
| B4b-03 | 工程模型：manifest、resman、reactor、config、.xlib 依赖 | 聚合工程端到端 |
| B4b-04 | 工具：plugin、repro、artifact、xpd、xmeta、tree/why/install | 命令输出一致 |
| B4b-05 | 对拍：XNull CLI vs Go CLI 全命令；B3-09 gate + 9 示例双路径 | 全绿 |
| B4c-01 | 冻结 golden（142 入口 C、97 负例、9 示例） | SHA-256 清单 |
| B4c-02 | 删除 Go 构建/测试/CLI；保留 C 运行时与 XNull 源码 | 仓库无生产 `*.go` |
| B4c-03 | 无 Go 环境全量构建/测试 | 新机器仅 C 工具链 |

### 约束

- B4b 期间 Go oracle 保留（keep 82），不得提前删除；
- XNull CLI 必须走 xparser/xlex + xnullc，不依赖 Go 前端；
- 每卡以 B3-09 gate 子集回归，禁止回退；
- B4c 前必须冻结 golden；删除 Go 后不可回滚。

### 风险

- xparser/xlex 的原生语义差异（B2 遗留 42/126）可能阻塞 CLI 源码解析；
- `dev test` 的缓存/分片与 Go 结果一致性；
- 4GB 峰值内存需在 CI 上评估。

## 建议顺序

1. B4b-01 CLI bootstrap + 9 示例；
2. B4b-02 dev test；
3. B4b-03/04 工程工具；
4. B4b-05 全命令对拍；
5. B4c 冻结/删除/无 Go 验证。

## 当前基线

- main：B3-09 PASS（142/0）、B3-10 PASS、B4a PASS；
- xn-s4 固定点 sha256：`347908a9…a75b43`；
- Go 清单：keep 82 / replace 40 / delete 217 / evidence 29。
