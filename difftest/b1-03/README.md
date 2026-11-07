# QA1-B1-03 独立复验记录

## B1-03：122 文件差分

```bash
bash difftest/b1-03/verify-b1-03.sh
# files=122 diffs=0 errors=0
```

- 语料：B1-00 基线 `7df123d` 的 122 个 `.x`（`git archive` 导出）
- Go oracle：`0d8c985` 的 `impl/cmd/xnfmt`（自行构建）
- XNull formatter：`0d8c985` 的 `impl/xnfmt/xnfmt.x`（用同树 `xnull` 构建）
- 结果：**0 差异、0 错误**；另跑 main 155 文件：**0 差异、0 错误**
- 未引用 E4 的 evidence/结论；二进制由 QA1 从提交重建。

## ERR/PKG/TUPLE/ENTRY 现有验收复跑

```bash
bash difftest/b1-03/verify-acceptance.sh
# ERR: 1 FAIL（叶子用例）
# PKG/TUPLE/ENTRY: 0 FAIL
```

FAIL 清单（1 项）：

| # | 项 | 说明 |
|---|---|---|
| 1 | `TestQAERR01Runtime/闭包try失败不触发外层errdefer` | 已知期望顺序问题：实际无 `outer-e`，外层 `errdefer` 未误触发；现有 QA 期望写成 `after-call, outer-ok, outer-d`，与 S1 §10.3 顺序矛盾。属测试期望待修，不是实现回归。 |

分项：
- ERR：sema QA 用例 exit 0；interp QA 用例 exit 1（仅上表 1 项）
- PKG：8 PASS / 0 FAIL
- TUPLE：22 PASS / 0 FAIL
- ENTRY：interp 9 PASS、cli 9 PASS、codegen 18 PASS；0 FAIL

## 口径

- 只报 FAIL 叶子用例；聚合父测试 `TestQAERR01Runtime` 不重复计数。
- 不修改任何测试期望；该 ERR 项保留为 FAIL，交前端线修期望。
