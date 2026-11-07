# 接力棒：XNFMT-CI

- **卡片ID**：XNFMT-CI（xnfmt 纳入 CI 与发布产物）— **状态：DONE（pod `f43fe75`，待 owner 合并）**
- **输入**（上游产物/条款/接口）：
  - `impl/cmd/xnfmt`（B1-01 Go oracle，规范 v1.0.0；`xnfmt <file>` / `--check` 三态）
  - `ci/run.sh`（现有 10 项：01 gofmt+vet、02 go test、03 C 运行时、04–09 桩、10 旧扩展名扫描）
  - `evidence/M6-B1-01/sha256-table.txt`（122 个 `.x` 的格式化基线）
  - `死命令.md` 第 1 号 §1.6（B1 工具必须进入正式发布物）
- **输出文件**（精确路径，计划）：
  - `ci/run.sh` 第 11 项「xnfmt 全仓校验」：全仓幂等双跑 + `ci/xnfmt-baseline.txt` 存量闸门（新增未格式化即 FAIL，baseline 只减不增）
  - `ci/README.md`：11 项表
  - `ci/xnfmt-baseline.txt`：冻结 19 个既有未规范化文件
  - `scripts/build_release.sh`：产出 `xnull` + `xnfmt` + `SHA256SUMS`
  - `evidence/XNFMT-CI/{command.txt,ci-list.out,ci-full.out,only11-positive.out,only11-negative.out,release.out,acceptance.md}`
- **commit**：`f43fe75`（`ci: add xnfmt repo-wide gate and release artifacts`；pod/e6-toolchain）
- **验证命令**（可复制）：
  ```bash
  bash ci/run.sh --list | grep -c '^'          # 期望 11
  bash ci/run.sh --only 11                    # 期望 0
  bash ci/run.sh --only 10                    # 回归：0
  bash scripts/build_release.sh /tmp/release  # 期望 0，产物含 xnull、xnfmt
  shasum -a 256 /tmp/release/*
  ```
- **已知缺口/风险**：
  1. CI 的 04–09 仍是 SKIP 桩；第 11 项只覆盖 xnfmt，不代表全量 CI 完整。
  2. 19 个存量文件仍在 baseline（examples/evidence/tests），一次性格式化会改历史证据，需董事会/CEO 决策；在此之前 baseline 只减不增。
  3. 发布脚本仅本机平台二进制，无交叉编译/签名；产物目录缺省 `dist/`（已 gitignore），发布口径归 COO。
  4. 尚未合并 main（E4 负责本次合并线）。
- **下一步**（谁接、做什么）：E4/owner 合并 `pod/e6-toolchain` 后，CI 第 11 项在 main 生效；COO 用 `scripts/build_release.sh` 出发布包；E6 下一卡待派。
- **上一棒**：`handoff/IDE-SOURCE.md`（DONE，main `6b6e987`/`9bf370c`）。
- **下一棒**：待派（E6 当前 WIP：本卡待验收；无并行开发卡）。
