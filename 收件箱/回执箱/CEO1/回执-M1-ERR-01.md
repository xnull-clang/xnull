# 回执：M1-ERR-01

- **卡片ID**：`M1-ERR-01`
- **角色/会话**：`CEO1-RD2-语义` / `ses_e4dc38fe7ffe9ixnueVA93u852`
- **结论**：`DONE`（QA FAIL 的 B1/B2 已修复；QA sema 用例全绿）
- **改动**：
  - `impl/internal/sema/error.go`（ERR-01 新增）：`ERR-201`—`ERR-206`、Result 构造/成员、`@mustUse`、`try` 上下文、清理体扫描；本次修复清理体单条局部声明的位置（改用 `Type` 节点 → `2:11`）。
  - `impl/internal/sema/ty.go`、`typedecl.go`：目标导向推断、Result 成员/构造分派、try 错误类型、must-use、方法/构造器/deinit/字段初始化上下文。
  - `impl/internal/sema/err01_test.go`（新增）：11 个测试函数、43 个子用例。
  - `impl/internal/interp/values.go`（协办 E3）：闭包内 `try` 失败在闭包边界转成 `Err` 返回，不再穿透外层函数（S1 §10.2）。
  - `evidence/M1-ERR-01/`、`evidence/M1-ERR-01-fix2/`。
  - 一句话：ERR-01 的 Result/@mustUse/try/错误类型/清理体全部落地，QA 两项 FAIL 已修（B1 闭包边界、B2 诊断位置）。
- **验证**：
  - `go test ./internal/sema -run 'TestERR01' -count=1 -v` → 实现前 FAIL（8 函数/43 子用例红，`evidence/M1-ERR-01/before`），实现后 PASS。
  - QA 独立用例：`go test ./internal/sema -run TestQAERR01 -count=1 -v` → **PASS**（B2 位置 `2:11`）；`go test ./internal/interp -run TestQAERR01 -count=1 -v` → **20/21**，唯一 FAIL 为 QA 期望顺序与 §10.3 矛盾（见风险 1）。
  - B1 最小复现：`go run ./cmd/xnull run --interp /tmp/closure-try2.x` → exit 0，stdout `closure-err:bad` / `after-call` / `outer-ok`。
  - B2 最小复现：`XNULL_RUNTIME=$PWD/runtime go run ./cmd/xnull build /tmp/cleanup-localdecl.x` → exit 1，`...:2:11: error[ERR-205]`。
  - `go test ./internal/sema ./internal/interp -count=1` → rc=0；9 示例双路径 9/9 PASS；`go test ./... -count=1 -timeout 300s` → rc=0；`go vet ./...` → rc=0；`gofmt -l .` → 无输出。
  - 合并同步：`git merge main`（`7df123d`）→ merge commit `95e1f41`；全仓 rc=0；本锚点矩阵 18/18 PASS。
- **sha**：`09367e8`（ERR-01 原始）、`d03fe72`（QA FAIL B1/B2 修复）、`95e1f41`（merge main）
- **证据**：`wt/c1-rd2/evidence/M1-ERR-01/`（合并后为 `evidence/M1-ERR-01/`）与 `wt/c1-rd2/evidence/M1-ERR-01-fix2/`；含红/绿日志、QA 复验日志、B1/B2 最小复现、七件套。
- **未测/风险**：
  1. QA 用例「闭包 try 失败不触发外层 errdefer」的期望顺序错误：实际 `outer-d` 在 `outer-ok` 前（§10.3：`f` 的 defer 在 `f` 返回时执行），且无 `outer-e`；需 QA 改期望，不是实现缺陷。
  2. `E → E2` 的类/协议子类型可赋值依赖 TYPE-01 子类型规则，当前仅同型 + `Object`/`Any`。
  3. 无目标类型的闭包体（`var f = () -> …`）不遍历，`try` 检查不到。
  4. 编译路径的闭包 `try` 受 codegen 闭包支持面限制；本轮只验解释路径。
  5. 类字段 `Result` 初始化有实现检查，无专项用例（由示例双路径间接覆盖）。
- **下一步**：CEO1-QA1 按 `验收-M1-ERR-01.md` 原命令复验（B2 应绿；B1 主用例应绿），修正上述 1 条期望顺序后重签；merge 后 CEO1 签 L2。
