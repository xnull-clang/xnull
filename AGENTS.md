# AGENTS.md

## 0. 开机自检（强制）

做任何事之前，先运行：
`python3 .agent/bin/boot.py`

- `BOOT: BLOCKED`：先处理列出的阻塞项，不得跳过。
- `BOOT: OK` / `BOOT: REPAIRED`：按 `NEXT:` 执行。
- 它负责：承接未完成复盘、修复权限漂移、核对当前批次与角色。
- 插件 `boot-guard` 在每次提交前自动执行上述检查；`BLOCKED` 时原任务暂存到 `.agent/state/blocked/`，不会被执行。

## 角色边界

- **rule-writer**：只写规则/规范/验收谓词；不派发、不盯盘、不验收、不碰 worker worktree。
- **orchestrator**：读规则、跑 preflight、派发、盯盘、验收、更新 queue；不写代码。
- **worker**：只执行自己 owner 的批次；不接别人的批次、不调度。
- **reviewer**：只读审计；不改文件。
- 当前会话角色由 `.agent/roles.json` 声明；`boot.py` 按角色给 NEXT，不按全局批次状态给 NEXT。
- 规则优先级：`LOCAL_RULES.md` > 本文件 > 任务合同；不改规范/发明 API，新约定先写规范并等签字。

## 开工前 60 秒

1. 读 `LOCAL_RULES.md`（若存在）。
2. 读 `.agent/AGENT-LEARNING.md` 与 `.agent/corrections.md` 的 active 条目（若存在）。
3. 读本次任务的批次合同/计划：边界、验收谓词、停止白名单。
4. 涉及共享文件时，先确认写入归属与合并顺序。
5. 若 `.agent/state/retro-due` 存在，先完成对应复盘并跑 `check.py`，再开新活。

## 收工前 60 秒

1. 有没有已记录的纠正复发？
2. 本批是否 RED / 返工 / 卡死？是则写 `.agent/retros/<date>-<batch>.md`。
3. 有纠正重复 ≥2 次或可机械判定？升级到 L2/L3，或提出升级。
4. 只有规则变化时才改本文件，保持 ≤80 行。

## 行为硬规则

- 一批 = 一个用户可见停点。批内不逐条门禁/提交/汇报；批末一次。
- 只有四类可停：红门修不了、规范缺失需签字、破坏性操作、用户叫停。
- 已隔离 ≠ 已解决；已标记 ≠ 已完成；已延期 ≠ 已关闭。
- PASS ≠ Verified；自述 ≠ 证据。完成必须有命令输出、提交、工作区状态。
- 派发新批次前必须过 `python3 .agent/bin/preflight.py <batch> --session <ses>`；只有 `DISPATCH: GO` 才能调用 `batch.sh`。
- 依赖未 accepted → WAIT；写集重叠 → CONFLICT；角色/工作区不满足 → BLOCKED。
- 汇报：先结论，再证据，再需要用户决定的事。

## 纠错索引

| ID | 规则 | 级别 | 位置 |
|---|---|---|---|
| C-0001 | 批内不停，批末一次收尾 | L2 | `LOCAL_RULES.md` 第 5 号 |
| C-0002 | 收口只有 Verified/RED | L2 | `LOCAL_RULES.md` 第 6 号 |
| C-0003 | 标记不是完成 | L2 | MINI-1.0 闭包账本 |
| C-0004 | 隔离不是解决 | L2 | `EXECUTION-PLAN.md` §4.4（xdk-2） |
| C-0005 | 后台要有 watchdog | L2 | 脚本待建 |
| C-0006 | 汇报结论先行 | L1 | 本文件 |
| C-0007 | 调度台不写代码 | L3 | `.opencode/agents/orchestrator.md` |
| C-0008 | L3 测试通过即生效 | L2 | `.agent/AGENT-LEARNING.md` |
| C-0009 | 复盘 due 只能指向批次草稿 | L3 | `.agent/bin/check.py` |
| C-0010 | 派发前做依赖/写集检查 | L2 | `.agent/DISPATCH.md` |
| C-0011 | 规则层不调度 | L2 | `.agent/roles.json` |

## 升级

- L1 纠错账本：agent 自动写。
- L2 硬规则/合同：agent 提议，用户签字。
- L3 权限/脚本/测试：`python3 .agent/bin/promote.py apply <ID>`；测试通过即生效，失败自动回滚；回滚用 `rollback`。
- L4 退役：标 `superseded`，移出索引。

## 承接

- 批次用 `.agent/bin/batch.sh` 跑；它跑完一定接 `.agent/bin/retro-run.sh`，不靠谁记得调用。
- 复盘未完成会留下 `.agent/state/retro-due`，下次开工先处理。

## 本地文件

详细纠错、复盘、脚本在 `.agent/`（本地，不提交）。团队共享只保留本文件。
若 `.agent/` 不存在，跳过本地账本，不要创建空文件。
