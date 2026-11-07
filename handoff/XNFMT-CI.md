# 接力棒：XNFMT-CI

- **卡片ID**：XNFMT-CI（xnfmt 纳入 CI 与发布产物）
- **输入**（上游产物/条款/接口）：
  - `impl/cmd/xnfmt`（B1-01 Go oracle，规范 v1.0.0；`xnfmt <file>` / `--check` 三态）
  - `ci/run.sh`（现有 10 项：01 gofmt+vet、02 go test、03 C 运行时、04–09 桩、10 旧扩展名扫描）
  - `evidence/M6-B1-01/sha256-table.txt`（122 个 `.x` 的格式化基线）
  - `死命令.md` 第 1 号 §1.6（B1 工具必须进入正式发布物）
- **输出文件**（精确路径，计划）：
  - `ci/run.sh`：新增第 11 项「xnfmt 全仓校验」——`xnfmt --check` 对 `git ls-files '*.x'`；另对已规范文件做幂等双跑（`patch` 比对），失败即 FAIL
  - `ci/README.md`：11 项表 + 第 11 项判据
  - 发布产物：`impl/runtime/build_rt.sh` 同级新增 `scripts/build_release.sh`（或 `impl/scripts/`），把 `xnull`、`xnfmt` 一并构建到发布目录并输出 sha256 清单
  - `evidence/XNFMT-CI/`：CI 运行记录、发布产物 sha 清单
- **commit**：待写（开工后见 `git log --oneline -- ci/ impl/scripts`）
- **验证命令**（可复制）：
  ```bash
  bash ci/run.sh --list | grep -c '^'          # 期望 11
  bash ci/run.sh --only 11                    # 期望 0
  bash ci/run.sh --only 10                    # 回归：0
  bash scripts/build_release.sh /tmp/release  # 期望 0，产物含 xnull、xnfmt
  shasum -a 256 /tmp/release/*
  ```
- **已知缺口/风险**：
  1. CI 现有多项为 SKIP 桩（04–09），第 11 项只覆盖格式化，不代表全量 CI 完整。
  2. 全仓 `--check` 目前 exit 1（12 个既有文件未规范化，B1-01 只做差分不改写）；第 11 项若直接要求 0 会误红，需先决定「CI 只校验新改动文件」或「一次性格式化合并」——属董事会/CEO 决策，执行位不得自行改写仓库。
  3. 发布产物目录与命名口径未定（`dist/` vs `release/`，是否带版本号），需 COO 确认。
- **下一步**（谁接、做什么）：E6 开工第 11 项与发布脚本；先与 QA1 确认「CI 检查范围」口径，再落代码；完成后写本棒下一棒到 `handoff/<下一卡>.md`。
- **上一棒**：`handoff/IDE-SOURCE.md`（DONE，main `6b6e987`/`9bf370c`）。
- **下一棒**：待派。
