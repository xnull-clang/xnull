# 三司写入域与 worktree 分配 v1.0.0

> **制定：CEO3（三司司长）**　**时间：2026-11-07**　**依据：董事会判决 v1.6.0 第 2.3 条、第 3 条、第 4 条第 4/5 项；v1.3.0 第 2 条**
> **性质：执行边界文件。不派工、不签门；只规定「谁能写哪个文件」与「写权何时生效」。**

---

## 一、三司交付域

| 角色 | 会话 | 交付域 | 可写路径（需卡） | 不可写 |
|---|---|---|---|---|
| RD1 | `CEO3-RD1-工具链` | xdk / cli / devtool | `impl/lib/xdk/**`、`impl/internal/cli/**`、`impl/internal/devtool/**` | `impl/internal/{xfront,sema,codegen,interp}/**`、`impl/runtime/**` |
| RD2 | `CEO3-RD2-构建与CI` | CI、构建、产物 | `ci/**`、`impl/cmd/**` | `impl/runtime/**`（E5 域）、`impl/internal/**` 生产代码 |
| RD3 | `CEO3-RD3-测试基建` | 差分、变异、夹具 | `difftest/**`、`impl/Tests/**` | 生产代码（`impl/internal/**`、`impl/lib/**`、`impl/runtime/**`） |
| PM | `CEO3-PM-产品` | 条款与验收口径 | `收件箱/CEO3/**` | 全部代码与测试 |
| PJ | `CEO3-PJ-项目` | 拆卡、排期、证据完整性 | `收件箱/CEO3/**` | 全部代码与测试 |
| QA1 | `CEO3-QA1-独立验收` | L1 独立验收 | 测试文件（按卡分派） | 生产代码；自己写过的测试不得自签 |
| QA2 | `CEO3-QA2-差分与变异` | 差分/变异/防假绿 | 测试文件（按卡分派） | 生产代码；变异报告不等于 L1 签字 |

**硬规则（v1.6.0 §3/§4）：**
1. **一文件一写入者**：写权只来自任务卡上的文件清单，口头授权无效。
2. 同一时刻同一文件只有一个会话可写；其余只读。
3. 任何 RD 不得改 main、不得直接 commit 到 `main`、不得 push；提交只落 `pod/c3-rd*`。
4. 无卡只读，包括“顺手修一行”。
5. 两人都认为要改同一文件 → 停手报 CEO3 指定唯一写者；技术方案争议交 CTO，不自行合并。

---

## 二、与 E6 的同域划界

E6 是 `impl/lib/xdk/**`、`impl/internal/cli/**`、`impl/cmd/**`、`ci/**` 的**原主责**（v1.6.0 §3）；CEO3-RD1/RD2 是增援。

| 域 | 原主责 | 增援 | S0-28 验收前 | S0-28 验收后 |
|---|---|---|---|---|
| `impl/lib/xdk/**` | E6 | RD1 | **只读** | E6 保留主责；RD1 只写卡上列明文件 |
| `impl/internal/cli/**` | E6 | RD1 | **只读** | 同上 |
| `impl/internal/devtool/**` | E6 | RD1 | **只读** | 同上 |
| `ci/**` | E6 | RD2 | **只读** | 同上；CI 第 10 项公开侧修正优先给 RD2 |
| `impl/cmd/**` | E6 | RD2 | **只读** | 同上 |

**当前事实**（2026-11-07 复核）：
- `wt/e6-toolchain` 在 `pod/e6-toolchain` @ `81ec33d`，含 S0-04b（CI 4 文件）与 S0-28（9 worktree）两个提交；
- main 仍在 `dfcf033`，`git ls-files ci` = **0**；
- E6 工作树有未跟踪的 `evidence/S0-04/`、`evidence/S0-21*/artifact.sha256` 等，**尚未入 main**。

**冲突处理**：E6 与 RD1/RD2 同时主张同一文件时，E6 优先（原主责），RD 改子卡或等 E6 释放；CEO3 只裁写权，不裁技术方案。

---

## 三、与 QA1 的同域划界

原始 `QA1-独立质量组` 保留原职权（v1.6.0 §3），写入域为 `impl/Tests/**`、`difftest/**`、`conformance/**`；CEO3-RD3、CEO3-QA1、CEO3-QA2 与之同域。

| 场景 | 唯一写者 | L1 签署人 | 说明 |
|---|---|---|---|
| 三司生产卡（RD1/RD2） | 卡上 RD | **CEO3-QA1** | 实现者不自验；QA2 提供差分/变异报告 |
| 三司测试基建卡（RD3） | RD3 | **原始 QA1 或 CEO3-QA2** | RD3 自写测试不得自签 |
| 三司 QA 自建测试卡 | CEO3-QA1 或 QA2 | **原始 QA1** | 自建自签视为反作弊 §4.4(7) |
| 跨司卡（一司/二司） | 归口司 RD | 归口司 QA | CEO3 只审证据、不改门禁结论 |

**规则：**
1. 每司 L1 由**本司 QA** 签；`CEO3-QA1-独立验收` 是三司 L1 默认签署人。
2. 原始 `QA1-独立质量组` 保留全项目独立验收权；同一张卡不得由两人同时签 L1。
3. QA2 的差分/变异报告是**输入**，不是签字；L1 签字人必须未参与该卡实现。
4. L2 由 CEO1 签，L4 董事会；CEO2/CEO3 不签 L2。
5. QA 写测试文件必须有卡并写明文件路径；不得改被测代码、不得改期望值让测试变绿。

---

## 四、S0-28 worktree 分配（预分配，未生效）

**事实**：`git worktree list` 已有 `wt/c3-rd1/2/3`（分支 `pod/c3-rd1/2/3`，均基于 `dfcf033`，工作区 0 行脏）；对应提交 `81ec33d` 只在 `pod/e6-toolchain`，**main 无 `evidence/S0-28/`**，S0-28 未验收。

| worktree | 分支 | 基线 | 分配 | 写权状态 |
|---|---|---|---|---|
| `wt/c3-rd1` | `pod/c3-rd1` | `dfcf033` | CEO3-RD1-工具链 | **预分配，只读** |
| `wt/c3-rd2` | `pod/c3-rd2` | `dfcf033` | CEO3-RD2-构建与CI | **预分配，只读** |
| `wt/c3-rd3` | `pod/c3-rd3` | `dfcf033` | CEO3-RD3-测试基建 | **预分配，只读** |

**写权生效条件（缺一不生效）：**
1. `evidence/S0-28/` 七件套进入 main（当前仅在 `pod/e6-toolchain` @ `81ec33d`）；
2. 三司 QA1 签 L1（S0-28 属三司卡）；
3. CEO1 签 L2；
4. CEO3 在本文件更新「写权状态」为已生效并登记卡号。

**当前授权结论：三位 RD 一律只读。** 未生效前只能做盘点、读代码、写 `收件箱/CEO3/*-首轮.md`，不得写生产代码、不得 commit。

**QA 的 worktree**：v1.6.0 只批了每司 3 个研发 worktree（共 9 个），QA 无独立 worktree。QA 写测试文件时按卡使用被测卡的 worktree，且必须与 RD 分时（RD 交付、CEO3 记录 sha 后 QA 才写入），不得与 RD 同时改同一目录。若后续需要独立 `wt/c3-qa`，由 CEO3 报董事会，不自行创建。

---

## 五、提交与证据

1. 每个 RD 一个分支一张卡；commit message 带卡号；`git status` 提交前必须干净。
2. 证据按七件套落 `evidence/<task-id>/`：`command.txt`、`stdout.txt`、`stderr.txt`、`exit_code.txt`、`sha.txt`、`artifact.sha256`、`acceptance.md`。
3. `acceptance.md` 必须含 **L1 签署人姓名 + 时间 + 结论**；执行侧自检不得代替签字。
4. CEO3 只汇总缺项、不改门禁结论；L1 结论由 QA 出，L2 由 CEO1 出。

---

## 六、变更记录

| 时间 | 动作 | 明细 |
|---|---|---|
| 2026-11-07 | 建档 | 依 v1.6.0 划三司写入域、E6/QA1 同域边界、c3-rd1/2/3 预分配；因 S0-28 未验收，写权一律未生效 |
