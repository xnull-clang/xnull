# 验收-M1-PKG-01（回执箱版）

> **验收人**：CEO1-QA2-回归　**实现者**：CEO1-RD1
> **结论：FAIL**
> **验收点**：`a6fb48d`（`39552bc` 已将 main@2c00cf5 合入 pod/c1-rd1；PKG-01 代码 `9bb6bef`）
> **详细版**：`收件箱/CEO1/验收-M1-PKG-01.md`　**证据**：`收件箱/CEO1/evidence-M1-PKG-01/`

---

## 0. 当前判定（2026-11-07 复验，main `d349f6a`）：**FAIL**

逐项重审原 3 条失败项；E2 自有 8 个 PKG 测试全绿（8 PASS / 0 FAIL），但覆盖不到以下 3 项。

| 项 | 判据 | 期望 | 实测（main `d349f6a`） | 判定 |
|---|---|---|---|---|
| **F1** 同别名指向不同符号 | §3.5 别名消歧 | `RES-103` | `RES-102` 类型 `X`/`Y` 在包内重复声明 | **FAIL** |
| **F2** 合法多级 XDK 包 | §3.5（L1544） | 接受 `import xdk.net.http` | `RES-106`：`xdk.net` 没有导出符号 `http` | **FAIL** |
| **F3** 别名与同包裸导入同名 | §3.5 | `RES-103` | `RES-102` 类型 `X` 在包内重复声明 | **FAIL** |

复现：`wt/qa-1/evidence/QA1-anchors-2026-11-07/pkg/{f1,f2,f3,c1}.x`；原始输出 `.../logs/pkg-summary.txt`。
注：`c1.x`（同一别名 `P` 指向 `lib.a.X` 与 `lib.b.X`）同样报 `RES-102`，应为 `RES-103`。

**结论：FAIL，不翻转。** 拒绝行为存在，但码型与根因均不符 §3.5。

---

## 1. 结论

FAIL。49 个独立子用例 **46 PASS / 3 FAIL**，归为 2 条缺陷：

| # | 缺陷 | 性质 | 复现 | 期望 → 实际 |
|---|---|---|---|---|
| **F1** | 同包不同符号共用同一 `as` 别名，静默通过 | **本提交回归**（main@2c00cf5 正确报 `RES-103`） | `import lib.a.X as P` + `import lib.b.X as BX` + `import lib.a.Y as P` + `import lib.b.Y as BY` | `RES-103` → **无诊断** |
| **F2** | 合法多级 XDK 包被误拒 | 基线遗留；本卡宣称"包导入诊断闭合"未覆盖 | `import xdk.net.http` | 无诊断 → **`RES-106`** |
| F3 | 别名与同包裸导入简单名同名，静默通过 | 基线同类，非本提交引入 | `import lib.a.X as Y` + `import lib.b.X as BX` + `import lib.a.Y` | `RES-103` → **无诊断** |

根因：
- F1/F3：`impl/internal/sema/xdk.go:168` 把来源记为**包路径**，`:216` 用 `prev != b.src` 判重，同包不同符号被当成同一来源。
- F2：`xdk.go:123` 把 `len(p)==3` 一律当符号导入，无法区分 `xdk.text.Regex` 与 `xdk.net.http`。规范见 `XNull解决方案-第1部分-基础语法-v3.3.0.md:1544`。

---

## 2. 已跑命令与结果

| # | 命令（干净导出 `git archive a6fb48d`） | 结果 |
|---|---|---|
| 1 | `cd impl && go build ./...` | exit 0 |
| 2 | `go test ./internal/sema -count=1 -v` | **57 PASS / 0 FAIL**，`ok 2.642s` |
| 3 | `go vet ./internal/sema` | exit 0 |
| 4 | 独立用例 49 子项（`qa2_independent_test.go`，仅注入 /tmp 副本） | **46 PASS / 3 FAIL**（上表 F1/F2/F3） |
| 5 | `go build -o /tmp/xnull-qa2-a6 ./cmd/xnull`；`run --interp` vs `run` | 编译 exit 0 |
| 6 | `examples/multi/main.x` 双路径 `cmp` | stdout 逐字节一致，退出码 0/0，stderr 0 B |
| 7 | 9 个单文件示例逐个双路径 `cmp` | **9/9 一致**，退出码全 0/0 |
| 8 | main@2c00cf5 上跑 F1 复现（回归对照） | **PASS（`RES-103` 存在）** → 证明 F1 为回归 |
| 9 | 基线 81ec33d 上同用例 | PASS（`RES-103` 存在） |

> 合并态：`9bb6bef` 直接合 main@2c00cf5 曾在 `xdk.go` 冲突；`39552bc` 已解决（仅加 `sort.Strings(pkgs)`），`a6fb48d` 为合并后复跑点。sema 全绿（57/57）但覆盖不到上述 3 个失败项，不能据此判 PASS。

---

## 3. 未跑清单

1. 未跑全仓 `go test ./...`（本次只跑 `internal/sema`；codegen/interp 未跑，避免与在途合并相互污染）。
2. 未跑 xfront 全量（`a6fb48d` 含 NEG/GEN xfront 修复，未独立复验）。
3. 未跑 CLI 级导入诊断：`AnalyzeWithDeps` 尚未接 CLI（回执已声明），本次按 sema API 验收。
4. 未验完全限定名（§3.2 末条）与多包代码生成（`RES-109`，回执列为边界）。
5. 未跑覆盖率 / 变异 / 性能（不属本卡验收面）。
6. 未验依赖包自身的缺失导入诊断（`Package` 只带导入路径，多包切片边界）。

---

## 4. 证据路径

- 详细验收：`收件箱/CEO1/验收-M1-PKG-01.md`
- 原始输出：`收件箱/CEO1/evidence-M1-PKG-01/`
  - `merged-independent-sema.log`（49 子项，3 FAIL）
  - `merged-sema-full.log`（57 PASS）
  - `merged-vet.log`
  - `main-2c00cf5-alias.log`（回归对照：ReproA PASS）
  - `baseline-81ec33d-alias.log`
  - `merge-conflict.log`（历史冲突原文）
  - `qa2_independent_test.go`（独立用例全文）
  - `dualpath/`、`dualpath-merged9/`（双路径原始输出）
  - `sha.txt`（main / 9bb6bef / 39552bc / a6fb48d）

---

## 5. 复验通过条件

1. 别名判重改为比较"完整导入来源（包 + 符号）"或维护"已绑定名 → 符号身份"；同别名指向不同符号必须 `RES-103`（F1/F3）。
2. `xdk.<pkg>.<seg>`：`seg` 为已知符号才按符号导入，否则按多级包导入（F2）。
3. 补 3 条先红后绿用例；在 `a6fb48d` 上重跑 sema 全量 + 本 49 子项 + multi/9 示例双路径。
4. 交新 sha + 七件套；QA2 复验后方可改判 PASS。
