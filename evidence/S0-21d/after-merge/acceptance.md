# S0-21d/after-merge 自检结论（P0 合入后复跑）

> 合并：`main`（`9301ed4`，含 S1-02 `dff308d`、S1-06 `9301ed4`）→ `pod/e6-toolchain`，合并提交 `102310bfcf287f2235058fea812a0690714fa942`（非快进，双亲 `fa64db7`/`9301ed4`，无冲突）。
> 本文件追加于 `evidence/S0-21d/` 下，原 21d 文件一字未改。

## 七项硬指标（复跑）

| # | 指标 | 命令 | 实测 | 判定 |
|---|---|---|---|---|
| 1 | Go 静态与全量测试 | `go vet ./...`；`go test ./... -count=1 -timeout 300s` | vet=0；test=**0**，10 包全绿，`internal/codegen` **20.957s**（合并前 187.869s 超时、606s 挂起） | **绿** |
| 2 | C 运行时构建 | `sh impl/runtime/build_rt.sh` | 0；资源表/abi/std/weak-slot 全过 | 绿 |
| 3 | 工作区守门 | 主树 cwd + `evidence/S0-21d/bin/xnull dev check` | 0；五项 `[ok]`，EN 9 份对照 | 绿 |
| 4 | 公开布局守门 | `xnull/` cwd 同一二进制 | 0；五项 `[ok]`，与 #3 同构 | 绿 |
| 5 | 台账 | `dev ledger` 再生成 vs S0-21a golden | 120 行 / 101 条 / PASS 10；唯一差异为第 3 行生成器名 | 绿（白名单） |
| 6 | 资源生成器 | Go vs Python golden sha256 | 两侧 `2f88b9314adf77fc…` | 绿 |
| 7 | 无 Python 残留 | `find impl -name '*.py'`；`git grep 'impl/tools/.*\.py' -- ':!*.md' ':!evidence/**'` | find=0；产品代码 1 条（`resources.go:99` 冻结头，令 §1.1 例外） | 绿（按令 §1.1 口径） |

**整卡：通过（7/7 绿）。** 这是 E6 执行侧自检，不替代 QA1 独立验收与 CEO 门禁。

## 9 示例双路径（合并后重建二进制 `f89955da…`）

| 示例 | 解释器 | 编译路径 | stdout |
| --- | --- | --- | --- |
| ast-seed | 0 | 0 | 相同 |
| classes / containers / defer-cleanup / hello / lexer-seed / objlist / result-try | 0 | 0 | 相同 |
| parser-seed | **0** | 0 | 相同（合并前解释器挂起，21d 记 `interp=142`） |

9/9 stdout 相同、退出码 0。stderr：7/9 两路径完全相同；`ast-seed` 与 `parser-seed` 的编译路径有 cc `-Wparentheses-equality` 警告（生成代码多重括号），stdout 与退出码不受影响。`ast-seed` 在合并前即有同类警告（原 `dualpath/ast-seed.compiled.err` 1520 字节）；`parser-seed` 的警告随 S1-02 条件生成改动新出现，属噪声，非功能差异，**未改代码掩盖**，登记为观察项。

## 说明

- 两布局 check 按董事会令第 2 条使用 `evidence/S0-21d/bin/xnull`；该二进制构建于 `bc673cc`，**早于 S0-27**，内部仍是 mtime 判据。两布局本次为 0 是因为本机 mtime 恰好有利，不代表干净 clone 稳定——确定性由 `evidence/S0-27/` 的干净 clone + 3 次打乱证明；S0-24 门若要在意这一点，应改用 S0-27 的二进制或合并后的源码重新构建。
- 双路径必须使用合并后重建的二进制（`after-merge/bin/xnull`），否则无法证明 P0-1/P0-3 已修复。
