# CEO3-RD2 首轮盘点：构建与 CI

> **角色**：CEO3-RD2-构建与CI（三司编制，v1.6.0 §2.3）　**日期**：2026-11-07
> **依据**：董事会判决-三司编制与团队扩招 v1.6.0 第 2 条（编制与写入域）、第 5 条（首轮只读）
> **写入域**：`ci/**` + `impl/cmd/**`（v1.6.0 表列 `cmd/**`，本仓实际路径为 `impl/cmd/**`）
> **性质**：只读盘点。未改生产代码、未 commit、未派工、未碰他人文件。唯一写入物是本文件。
> **工作树快照**：main `dfcf033`；`ci/**` 仅存在于 `pod/e6-toolchain` @ `65e7dd4`（未合入 main）。

---

## 一、结论摘要

1. **`ci/**` 不在 main**：`git ls-files ci | wc -l` = **0**；main 连 `ci/` 目录都不存在，干净 clone 无法跑任何门禁。这既是 ERR-005，也是本域所有卡的前置。
2. **十项里 6 项是 SKIP 桩，但整体退出码仍是 0**（实测 `PASS=4 FAIL=0 SKIP=6 → exit 0`）。当前 CI 的"绿"不构成任何门禁结论。
3. **第 02 项静默假绿**：`ci/run.sh:63` 无 `-count=1`，实测 8 个测试包全部 `(cached)`，590ms 判 PASS——一个测试都没真跑。
4. **产物链整体缺失**：CI 十项无 `go build`，第 08 项「产物与 sha」是桩；二进制从未由 CI 产出，无 sha256 清单、无交叉编译、无版本注入、无 `target/` 布局、`git tag` = 0。
5. **干净 clone 不可复现门禁**：`xnull/` 是被 `.gitignore` 排除的嵌套仓库，`dev check` 在干净 clone 下 `EN 快照同步 FAIL`（exit 1）。第 05 项要接线，先得解决这个未入库依赖。

---

## 二、域盘点

### 2.1 文件清单（实测）

| 路径 | 行数 | 状态（main） | 说明 |
|---|---:|---|---|
| `ci/run.sh` | 192 | **不存在**（`pod/e6-toolchain` 已提交） | 十项唯一入口 |
| `ci/lib.sh` | 135 | **不存在**（同上） | run_step / skip_step / ci_summary |
| `ci/README.md` | 32 | **不存在**（同上） | 十项状态表 |
| `ci/.out/.gitignore` | 1 | **不存在**（同上） | 内容 `*`，运行日志全忽略 |
| `impl/cmd/xnull/main.go` | 24 | 已入库 | 命令入口 + 信号处理（130） |
| `impl/cmd/xnpt/main.go` | 44 | 已入库 | 解析对照小工具，无测试、无构建目标、无归属卡 |

### 2.2 授权边界说明

- v1.6.0 给我的写入域是 `ci/**` + `impl/cmd/**`；**`ci/**` 在 main 上尚无一行**，所以本域当前"可写但无处可写"。
- 构建脚本 `impl/runtime/build_rt.sh`（C 运行时）与 `impl/internal/cli/**` **不在我域内**。本报告凡涉及这两个文件，只标"缺口 + 建议归属"，不主张写入。

---

## 三、CI 十项现状（实测，非文档抄录）

**复现**：`cd wt/e6-toolchain && CI_OUT_DIR=<临时目录> CI_COLOR=0 bash ci/run.sh`

```
PASS 01 gofmt+vet                       593ms
PASS 02 go test -timeout 120s ./...     590ms   ← 8 包全 (cached)
PASS 03 C 运行时构建                  140439ms
SKIP 04 示例双路径
SKIP 05 check_specs 六检
SKIP 06 台账再生成 diff
SKIP 07 泄漏扫描
SKIP 08 产物与 sha
SKIP 09 汇总 JSON
PASS 10 文件名扫描（禁旧扩展名）         177ms
—— 汇总：PASS=4 FAIL=0 SKIP=6，用时 142869ms ——
退出码：0
```

| # | 项 | 实测 | 判定依据 | 真实完成度与问题 |
|---|---|---|---|---|
| 01 | gofmt+vet | PASS 593ms | `run.sh:49-60` | 真实现。仅 gofmt+vet，无 staticcheck/golangci；无 Go 版本断言（go.mod 1.27，实测 1.27.3，CI 不校验）。 |
| 02 | go test | PASS 590ms | `run.sh:62-64` | **假绿**。日志逐行 `(cached)`；冷跑同一命令需 ~124s（codegen 单包 124.005s）。且 `-timeout 120s` 是单测试二进制上限，冷跑已贴线，无余量。 |
| 03 | C 运行时构建 | PASS 140.4s | `run.sh:67-69` → `impl/runtime/build_rt.sh` | 真实现，但用固定 `/tmp/xnull_test_*` 路径（`build_rt.sh:5-23`），多 worktree/并行 CI 互踩；产物不落 `ci/.out`；不记录 cc 版本（与 `impl/docs/runtime-contract.md:75` P-07「缓存键须含 cc 版本串」相悖）。 |
| 04 | 示例双路径 | SKIP | `run.sh:72-74` | 桩。底层能力其实齐备：`examples/*.x` 9 个 + `examples/multi`，`xnull run` 有编译/解释双路径（`cli.go:186-226`）。 |
| 05 | check_specs 六检 | SKIP | `run.sh:75-77` | 桩。底层已实现：`go run ./cmd/xnull dev check <root>`，实测 0.32s 全绿六项——**只差接线**。但干净 clone 下 FAIL，见 G8。 |
| 06 | 台账再生成 diff | SKIP | `run.sh:78-80` | 桩。`dev ledger` 已实现，只差"再生成 + `git diff --exit-code`"。 |
| 07 | 泄漏扫描 | SKIP | `run.sh:81-83` | 桩。无判据定义。 |
| 08 | 产物与 sha | SKIP | `run.sh:84-86` | 桩。**CI 全程无 `go build`**，业务二进制从不产出。 |
| 09 | 汇总 JSON | SKIP | `run.sh:87-89` | 桩。每个步骤已输出 `steps.jsonl` 行，但无单一汇总文档、无 schema 校验。 |
| 10 | 文件名扫描 | PASS 177ms | `run.sh:93-122` | 真实现。排除 `wt/`、`xnull/`（`run.sh:102`），只查 tracked 文件；公共镜像仓库无守门。 |

**退出码语义（`lib.sh:118-127`）**：FAIL>0 → 1；PASS=0 且 SKIP>0 → 2；**其余 → 0**。所以 PASS+SKIP 混合一律 0，与「门禁通过」不可区分。

---

## 四、构建 / 产物缺口（12 条）

| 编号 | 缺口 | 证据 | 影响 | 严重度 |
|---|---|---|---|---|
| **G1** | `ci/**` 未入 main，干净 clone 无门禁 | `git ls-files ci` = 0；main 无 `ci/`；干净 clone 实测 `ls ci` → No such file | 门禁不可被 clone 复现；「修复 sha 进 CI 通过」无法机械满足 | **P0**（= ERR-005） |
| **G2** | SKIP 不算失败，混合态退出 0 | 实测 `PASS=4 SKIP=6 → exit 0`；`lib.sh:118-127` | 60% 未实现的 CI 对外表现为"通过"，门禁结论无意义 | **P0** |
| **G3** | 第 02 项命中测试缓存，零测试跑也 PASS | `run.sh:63` 无 `-count=1`；日志 8 包全 `(cached)`，590ms；README 的验收入口却是 `go test ./... -count=1`（`impl/README.md:94`） | 回归可被"上次绿"冒充；CI 与文档口径不一致 | **P0** |
| **G4** | 无产物、无 sha 锚点 | 第 08 项 SKIP；CI 无 `go build`；`evidence/*/artifact.sha256` 靠手工（CEO3 审计 EV-001—005 五项缺失） | 二进制与源码 commit 无绑定，问题无法归因到构建 | **P0** |
| **G5** | 交叉编译矩阵只写在文档里 | `impl/README.md:73` 声称 windows/amd64、linux/arm64「每次全量测试时一并验证」；十项无此项。实测两目标均可编译（6.7MB / 6.1MB），但产物落 `/tmp`、不留存、不算 sha | 发布面声明与实测脱节，等于无矩阵 | **P1** |
| **G6** | 构建不可复现、版本不绑定 commit | 无 `-trimpath`、无 `-buildvcs=false`、无 `-ldflags`；`cli.Version` 为硬编码常量 `"0.1.0-dev"`（`impl/internal/cli/cli.go:22`）；`go version -m` 显示 `mod xnull.dev/xnull (devel)` | 同源两次构建摘要可能不同；`xnull --version` 无法追溯来源 | **P1** |
| **G7** | 运行时构建脚本用固定 `/tmp` 路径 | `impl/runtime/build_rt.sh:5-23` 五套件 + res 均写 `/tmp/xnull_test_*` | 并行 CI、多 worktree 同时跑必互相覆盖；一次 PASS 可能是别人的二进制 | **P1** |
| **G8** | 门禁依赖未入库的嵌套仓库 | `.gitignore` 有 `/xnull/`；干净 clone 实测 `dev check` → `[FAIL] EN 快照同步（公开内容线） - en 目录不存在`，exit 1 | 第 05 项一旦接线，干净 clone 必红；「证据须可被干净 clone 复现」不成立 | **P1** |
| **G9** | 第 10 项守门有盲区 | `run.sh:102` 排除 `./xnull`、`./wt`；且只用 `git grep`（仅 tracked） | 公共镜像仓库出现旧扩展名不会被发现（当前实测 `.xn` = 0，但靠自觉） | **P2** |
| **G10** | 无发布产物链 | `git tag` = 0；无打包/checksums；S8 §5.1 规定 `package` 阶段产出 `target/<artifactId>-<version>.<ext>` + `.xmeta`（S8:478-479），`m4-codegen-design.md:211` 规定 `target/gen → target/obj → target/<name>`，均未落地；`xnull build/run/test/lock` 清单路径直接 `notImplemented`（`cli.go:98-105,132-136`）；仓库无 `target/` | 无版本、无包、无校验和 ⇒ 无法发布、无法回归比对 | **P1** |
| **G11** | 只有本地手工触发，结果不留痕 | 内部库无 remote（`git remote -v` 空）；无 `.github/workflows`；`ci/.out/.gitignore` = `*` | 无 push/PR 门禁；CI 结果不入证据，事后无法审计 | **P1** |
| **G12** | 质量面窄 | 无 `-race`、无覆盖率门槛、无 `-shuffle`/重复跑、无 `go mod verify`/离线复现、无工具链版本断言 | 数据竞争、flaky、依赖漂移全部漏检 | **P2** |

> 另注（供测试基建 RD3 参考，不在我域）：26 个 `_test.go`，`cmd/*` 两个包均 `[no test files]`；单包冷跑最慢 codegen 124s，测试侧无并行度优化。

---

## 五、前 3 张建议卡

> 卡号待 `CEO3-PJ` 落号（下用拟号，勿直接执行）；三卡全部以 **G1/ERR-005（`ci/**` 入 main）** 为前置，前置未清则三卡都只能开分支不能验。
> 每卡单一主责、写入域互不重叠，满足 v1.6.0 §4 第 3 条。

### 建议卡 1（拟 S0-29）`RD2-CI产物与sha`　严重度 P0

| 项 | 内容 |
|---|---|
| 目标 | 落地第 08 项「产物与 sha」：CI 真正构建 `xnull` 二进制，输出可复算的产物清单 |
| 主责 | CEO3-RD2　**写入域**：`ci/**`（新增 `ci/artifact.sh`）+ 第 08 项接线 |
| 依赖 | G1（`ci/**` 入 main）；G6 的版本注入需 `impl/internal/cli/cli.go:22` 由 `const` 改 `var`（**不在我域，需 CEO3 裁决归 RD1 或扩域 1 行**） |
| 动作 | ①`go build -trimpath -buildvcs=false -ldflags "-X xnull.dev/xnull/internal/cli.Version=<version>"` 产本机 + windows/amd64 + linux/arm64 三件；②产物落 `ci/.out/artifacts/<goos>-<goarch>/xnull`；③生成 `artifact.sha256`（`shasum -a 256` 排序后输出）+ `go version -m` 全文；④`<version>` 取 `git describe --tags --always --dirty`，与 `steps.jsonl` 同目录落 `build.json`；⑤第 08 项从 SKIP 改真实现 |
| 验收 | `bash ci/run.sh --only 08` exit 0；`ci/.out/artifacts` 下三件齐全且 `shasum -a 256 -c artifact.sha256` 全 OK；同一 commit 连跑两次 `artifact.sha256` 逐字节一致；`./ci/.out/artifacts/darwin-amd64/xnull --version` 输出含 commit 短 sha |
| 证据 | `evidence/<卡号>/` 七件套（由建议卡 3 的生成器产出） |
| 预估 | 1 人日；风险：交叉编译二进制在目标机仍需本地 `cc`（`runCompiled` 依赖运行时源码目录，`cli.go:186-200`），卡内须写明"矩阵验的是能构建，不验能运行" |

### 建议卡 2（拟 S0-30）`RD2-门禁语义与去缓存`　严重度 P0

| 项 | 内容 |
|---|---|
| 目标 | 让 CI 的退出码唯一代表「十项全部真跑且通过」，消灭 G2/G3 两类假绿 |
| 主责 | CEO3-RD2　**写入域**：`ci/**` |
| 依赖 | G1；无其他卡依赖，可与卡 1 并行（改 `run.sh`/`lib.sh` 与新增 `artifact.sh` 不冲突，但同文件 `run.sh` 须串行合并） |
| 动作 | ①`ci_summary` 增 `--strict`（门禁用）：SKIP>0 或 FAIL>0 一律 exit 1，新增 exit 3 = 「桩未实现」；②第 02 项改 `go test -count=1 -timeout 300s ./...`；③每步落 `started_at/ended_at/cmd/rc` 到 `steps.jsonl`；④`--strict` 下拒绝 `(cached)`：`go test` 输出含 `(cached)` 即 FAIL；⑤`--only` 模式保持现状（开发用），门禁用 `run.sh --strict` 全量 |
| 验收 | 当前桩态下 `bash ci/run.sh --strict` 必 exit 1（实测基线 `PASS=4 SKIP=6`）；`--only 02` 日志含 `-count=1` 且无 `(cached)`；连续两次全量跑，第 02 项耗时均 > 100s；`steps.jsonl` 每行含 `cmd` 字段 |
| 证据 | 前后两次 `steps.jsonl` + `step-02.log` 全文 |
| 预估 | 0.5 人日；风险：卡落时第 04—09 项若仍是桩，`--strict` 会让 CI 常态红——这是**预期行为**（红即真相），需 CEO3 在门禁口径里同步声明"桩态 CI 不得绿" |

### 建议卡 3（拟 S0-31）`RD2-证据生成器与干净clone`　严重度 P1

| 项 | 内容 |
|---|---|
| 目标 | 证据七件套不再手工拼装；门禁在干净 clone 下可复现 |
| 主责 | CEO3-RD2　**写入域**：`ci/**`（新增 `ci/evidence.sh`、`ci/clean-clone.sh`） |
| 依赖 | G1；G8 的 EN 快照离线化需 CEO3 裁决方案（见 §六 待裁决 3） |
| 动作 | ①`ci/evidence.sh <task-id> -- <cmd...>`：一次产出 `command.txt/stdout.txt/stderr.txt/exit_code.txt/sha.txt/artifact.sha256/acceptance.md`（acceptance 留签名栏，不代签）；②`ci/clean-clone.sh`：`git clone` 到临时目录，跑 `go build` + `bash ci/run.sh --strict`，任何依赖未入库即显式 FAIL 并指出路径；③把 `git ls-files ci \| wc -l ≥ 1` 作为脚本首检 |
| 验收 | `bash ci/evidence.sh S0-31 -- bash ci/run.sh --only 01` 后七件套齐全，`artifact.sha256` 可 `shasum -c` 通过；`bash ci/clean-clone.sh` 当前必 FAIL 且日志指出 `xnull/spec/en` 缺失（修复后转 PASS）；EV-001—005 五项按同一生成器补齐后 `git ls-files evidence` 各 +1 |
| 证据 | `evidence/S0-31/` 七件套 + clean-clone 日志 |
| 预估 | 1 人日；风险：`acceptance.md` 必须留空签名栏——生成器不得代替验收人签署，否则重演 S0-21 的"执行侧自检当验收" |

### 未进前三的两项（登记，不派工）

- **第 04/05/06 项接线**（示例双路径 / 六检 / 台账 diff）：底层能力已具备（`dev check` 0.32s 全绿、`dev ledger` 已实现、9+1 示例齐备），属 0.5 人日量级的低成本补齐，但都依赖 G8 或 `git diff` 干净树，建议排在卡 3 之后，归 CEO3-RD3（测试基建）或 RD1（工具链）。
- **第 07 项泄漏扫描**：**判据未定义**（`run.sh:81-83` 只有"未实现"三字）。这是 PM 域问题，RD2 不应自行发明判据——建议 CEO3-PM 先在工具链验收口径里定义"泄漏"（密钥？绝对路径？内部文档外泄？），否则此卡不可验收。

---

## 六、需要上级裁决的 3 件事（一次列全，不逐项打扰）

1. **`ci/**` 入 main 的归属**：ERR-005 / S0-04b 已在 CEO3 台账登记为「等 CEO2 派工」，责任人是 E6。我的三张卡都以此为前提。请 CEO3 明确：S0-04b 是否拆出「`ci/**` 入库」子卡并优先于本域任何新卡？在其完成前，我是否只做分支内改动？
2. **1 行扩域申请**：版本注入需把 `impl/internal/cli/cli.go:22` 的 `const Version` 改 `var`。该文件不在我域。请裁决：划给 CEO3-RD1，还是作为卡 1 的附条扩域给 RD2（改动 1 行，附 `git diff` 审查）。
3. **`xnull/` 嵌套仓库与 EN 快照的离线方案**（G8）：三选一——①在 main 内置 `spec/en` 快照副本（重、可能两源漂移）；②`dev check` 在快照缺失时降级为 SKIP 且 `--strict` 下 FAIL（轻，但门禁在干净 clone 必红）；③把 EN 快照判据移出 CI，改由公开仓库自身 workflows 承担（需公开仓库有 CI，当前没有）。我倾向 ②＋③ 组合，但这是口径决定，不是我能定的。

---

## 七、只读声明与复现命令

**未做**：未改 `ci/**`（main 上不存在）、未改 `impl/**`、未 commit、未建 worktree、未派工、未删任何文件。

**副作用**：仅在 `/private/var/.../opencode/` 下产生临时 CI 输出、交叉编译产物与一份干净 clone；`wt/e6-toolchain/ci/.out/` 未被我写入（`CI_OUT_DIR` 已重定向）。复核：`git -C . status --porcelain impl` = 0 行。

```bash
# 十项现状
cd wt/e6-toolchain && CI_OUT_DIR=$(mktemp -d) CI_COLOR=0 bash ci/run.sh

# 假绿证据（第 02 项）
grep -c '(cached)' "$CI_OUT_DIR/step-02.log"

# 冷跑基线
cd impl && go test -timeout 120s ./...          # codegen 单包 124.005s

# 入库状态
git ls-files ci | wc -l                          # 0
git tag | wc -l                                   # 0
git remote -v                                     # 空

# 干净 clone 的门禁可复现性
git clone -q . /tmp/cc && cd /tmp/cc/impl && go run ./cmd/xnull dev check ..
# → [FAIL] EN 快照同步（公开内容线） - en 目录不存在 ; exit status 1

# 交叉编译可行性（可构建，不等于可运行）
GOOS=windows GOARCH=amd64 go build -o /tmp/xnull.exe ./cmd/xnull   # 6,725,632 B
GOOS=linux   GOARCH=arm64 go build -o /tmp/xnull-arm64 ./cmd/xnull # 6,146,536 B
```

**下一步**：等 CEO3 就 §六 三项裁决 + PJ 落卡号；收到卡后按「单卡单分支 + 七件套证据 + `ci/run.sh --strict` 自检」执行。
