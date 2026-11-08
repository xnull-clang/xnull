# 会话操作约定（项目级）

> 本文件为安装件，不是任务单。完整说明见 `收件箱/会话命名与通讯约定-v1.0.0-2026-11-07.md`。
> **治理规则以 `ADR/ADR-001-治理重构.md` 为准（试行）；本文件与其冲突时，以 ADR-001 为准。**

## 死命令（最高优先级）

`死命令.md` 是最高优先级常设强制命令，冻结、不得修改、不得降级解释。**与本文件冲突时，以 `死命令.md` 为准。**
当前第 1 号：自举路线（借力先行，自举收口）——B0—B4 五道门，详见 `死命令.md`。

## 语言硬规则

所有会话的可见输出用中文：回复、回执、验收结论、文档标题与正文、代码注释。git 提交信息允许英文（沿用 fix/feat/docs 风格）。代码标识符、诊断码、协议名、命令保持原文。

## 治理记忆（ADR-001/002/005，试行已结束，锚点制）

1. **五线制**：3 条生产线——前端线 E2、自举线 E4、运行时线 E5；2 条支撑线——QA 线 QA1、发布线 COO。E6 属自举线执行工具链/CI/IDE，不单列生产线。
2. **董事会只做三件事**：门判定、owner 冲突仲裁、ADR 归档；不派工、不看板、不写快照。
3. **ADR 制**：决策一页（背景/决定/后果），签发即冻结；禁止同主题连环升版。
4. **SSOT**：唯一看板由脚本从 git + go test + 台账 + evidence 生成；手改即作废。停止手工看板、每小时快照、自动刷新器。
5. **WIP**：每 owner 最多 2 张卡（1 开发 + 1 待验收）；全线在途 ≤10。
6. **SLA**：P0（门禁/停工）≤2h；P1 当日；P2 周批。只有死命令、预算、公开发布需用户裁决。
7. **汇报四数**：本周 commit 数、锚点翻转数、全量测试绿/红、门进度。禁止以文件数/回执数/看板数为产出。
8. **回执只用于门证据**；普通任务不再逐卡写回执。门禁仍按死命令四件套。
9. **当前门**：M1 14/14、M2 29/29、S3 13/13、S4 11/11、S5 12/12、S6 10/10、S7 7/7、**S8 11/11**（`收件箱/门/S8门.md`）全部通过；S1–S8 全部锚点 PASS。定版清单 v1.0.1 与 SHA-256 已出；B2 前置新增 XDK-09 net 补齐（ADR-009）；B2 = XNull 重写 lexer+parser、AST 与 Go 版逐字节一致。
10. **预算**：B1 8h、B2 48h、B3 72h；B4 拆 a/b/c 各 24h。
11. **收线与合并**（ADR-005/006/010）：main 只有 INTEG 可写，生产线只提交 `pod/*`；合并前建 `handoff/merge.lock`；同一文件同时只允许一个 owner；跨线卡先出接口文档；单卡 30 分钟必须提交中间版本；合并红只报告不回滚；status.tsv/golden/BOARD 只由 SSOT/董事会更新。B2 前置：S1–S8 定版 + SHA-256 + net 补齐。

## 命名

- 新建：`<角色>-<任务卡ID>-<任务名>`，如 `E6-S0-18-建-worktree与分支`。
- 重启：`<原名称>｜重启<N>-<本次任务说明>-<YYYY-MM-DD>`，N 从 1 递增。
- 禁止「新会话」「临时」「测试」等无信息量标题。

## 创建与迁移（必须两步）

```bash
opencode api POST /api/session -d '{"title":"<角色>-<任务卡ID>-<任务名>"}'
opencode api POST /api/session/<SESSION_ID>/move -d '{"directory":"<目标目录>"}'
```

`POST /api/session` 的 `directory` 参数会被忽略，不调 `move` 就在错误目录开工。

## 投递与查询

```bash
opencode run -s <SESSION_ID> -m deepseek/deepseek-flash "<消息>"
opencode api POST /api/session/<SESSION_ID>/prompt -d '{"text":"<消息>"}'
opencode api GET  /api/session/<SESSION_ID>/message
opencode api GET  /api/session/<SESSION_ID>
```

- 投递必须显式带 `-m deepseek/deepseek-flash`；不带会命中区域封锁模型或 free 模型。
- 所有常驻会话固定 `deepseek/deepseek-flash`；发现 `opencode/deepseek-v4.1-flash-free` 立即用 `/model` 复位。
- 锁死后用 `/api/session/<id>/model` 复位：`{"model":{"providerID":"deepseek","id":"deepseek-flash"}}`。
- `prompt` 请求体里的 `model` 字段被忽略，只能先 `/model` 再投递。
- 结果看 `/message` 最后一条 `type:"idle"` 的 `outcome`；状态看 `/session/<id>` 的 `outcome`/`busy`/`idle`。

## 通讯

- 父 → 子：`subagent` 工具，带 `sessionID` 可续聊。
- 子 → 父：subagent 最终答复直接回传。
- 异步留痕：写 `收件箱/<角色>/回执-*.md`；`/inbox` 接口只读，写入走文件。

## 禁止

- 不建台账、不写巡检脚本、不代董事会跑 E1–E6。
- 不删含在途子会话的父会话（`session delete` 级联删除）。
