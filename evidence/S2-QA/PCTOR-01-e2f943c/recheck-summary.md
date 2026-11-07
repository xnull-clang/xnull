# PCTOR-01 复验摘要（main e2f943c）

- main ref：`e2f943cf01319544c655469f9f9a81df690964d9`（读取 `.git/refs/heads/main`，未运行 git 命令）
- binary：`/tmp/xnull-s2-e2f943c`，sha256 `baa515e915fb4d1cb653e1dbda5efbc15bab98cf74849b22df832b81a6e9c42d`
- 结果：**PASS，15/15 双路径**

## 明细

- A01–A05：interp+compiled 共 10，全部 rc=0 且输出一致（5 / 5 / 5 / 1\n2 / 5\n6）。
- R01–R05：check 共 5，全部 rc=1 + `TY-212` + 位置。
- 官方用例：`TestS2PCTORRules`、`TestS2CtorBodies` PASS。
- 回归：目标包全绿，`go vet` exit 0，`go test ./...` exit 0（当前主工作树）。
