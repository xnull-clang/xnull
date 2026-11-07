# 验收：M1-ENTRY-01（入口与启动，S1 §11）

>
> 本文件同步自主工作树 `wt/qa-1`（分支 `pod/qa-1`）；执行器与原始日志见
> `wt/qa-1/evidence/QA1-verify-2026-11-07/`。


> **验收人**：QA1（独立质量线）
> **结论：FAIL（2 项 P1 阻断：初始化 fatal 不终止、main 重载误判重复）**
> **复验点**：main `7262ff0`
> **用例**：`evidence/M1-ENTRY-01-qa/`（42 份源码，双路径）
# 验收：M1-ENTRY-01（入口与启动）—— C-10 / C-13 复验

> **验收人**：QA1（独立质量线）
> **结论：PASS**（C-10 6/6；C-13 重载在前已修复）
> **复验点**：main `91c89c0`（`bf03f5f` 已并入）
> **时间**：2026-11-07

---

## 一、结论

| 项 | 结果 |
|---|---|
| 检查表 C-01～C-22 | **20 PASS / 2 FAIL** |
| 阻断项 | D-01（初始化 fatal 编译路径不终止）、D-04（`main` 重载误判重复入口） |
| 已转绿 | D-02 `private`/`protected` 入口、D-03 泛型入口、D-05 初始化前向引用 |
| P2 未闭环 | D-06 fatal 退出码 134 vs 255、D-07 `str(Bool)`/`print(Bool)` 双路径分歧 |

**FAIL 不放行**。入口四形态、退出码、args、负例主体均已通过；两项 P1 仍违反 §11.2/§11.3。

---

## 二、检查表（逐项）

| # | 检查项 | 条款 | 结果 | 实测 |
|---|---|---|---|---|
| C-01 | `void main()` 可运行，退出码 0 | §11.2 | PASS | `v0`，rc=0（双路径） |
| C-02 | `Int main()` 返回值即退出码 | §11.2 | PASS | `i0`，rc=7（双路径） |
| C-03 | `void main(final String[] args)` | §11.2 | PASS | `va 0`，rc=0 |
| C-04 | `Int main(final String[] args)`（2 参透传） | §11.2 | PASS | `ia 2`，rc=5 |
| C-05 | `final` 可选 | §11.2 | PASS | a5 形态通过 |
| C-06 | 退出码 0/1/42/255 直通；256→0、300→44、-1→255 | §11.2 | PASS | 双路径一致 |
| C-07 | 顶层字段按声明顺序先于入口 | §4.3/§11.3 | PASS | `init 1 / init 2 / main 2` |
| C-08 | 初始化式读未初始化字段得零值不报错 | §4.3 | **PASS** | c2 双路径 `a=5 b=1`（原 interp FAIL 已修） |
| C-09 | 初始化式可调用其后声明函数 | §4.3 | **PASS** | c6 双路径 `read c=0 / main c=9` |
| C-10 | 初始化 fatal 终止且不调用入口 | §11.3/§10.4 | **FAIL** | c3/c7b/c7c/c7d compiled rc=0，main 被执行 |
| C-11 | 缺失入口拒绝 | §11.4 | PASS | `ENTRY-001` |
| C-12 | 同签名重复入口拒绝 | §11.4 | PASS | `ENTRY-002` |
| C-13 | 非匹配 `main` 重载是普通函数 | §11.2 | **FAIL** | `main()` + `main(Int)` 报 `ENTRY-002`（e3） |
| C-14 | 非 `static` 入口拒绝 | §11.2 | PASS | rc=1 |
| C-15 | 返回 `String`/`Bool` 拒绝 | §11.2 | PASS | `ENTRY-003` |
| C-16 | 参数 `Int`/`String`/双参拒绝 | §11.2 | PASS | `ENTRY-003` |
| C-17 | `private`/`protected` 入口拒绝 | §11.2 | **PASS** | e10/e12 → `ENTRY-003`（原 FAIL 已修） |
| C-18 | 泛型入口拒绝 | §11.2 | **PASS** | e11 → `ENTRY-003`（原 FAIL 已修） |
| C-19 | `args` 为新数组、不含程序名 | §11.2 | PASS | `n=0`；`n=2 ARG alpha ARG beta` |
| C-20 | 非 void 入口缺 return 拒绝 | §6.1 | PASS | e14 → `DA-103` |
| C-21 | 示例双路径一致 | M1 门禁 | PASS | **10/10** MATCH |
| C-22 | 全量测试回归 | 回归 | 未复跑 | 沿用 `M1-ENTRY-01` 9/9 包绿；本轮未跑 `go test ./...` |

---

## 三、失败项原样输出

```
c3_init_fatal   interp   rc=134  err=xnull: fatal: 除零
c3_init_fatal   compiled rc=0    out=MAIN-SHOULD-NOT-RUN
c7_runtime_divzero interp rc=134 err=xnull: fatal: 除零
c7_runtime_divzero compiled rc=0 out=MAIN-SHOULD-NOT-RUN
c7b             interp   rc=134  err=xnull: fatal: 除零
c7b             compiled rc=0    out=a=0
c7c             interp   rc=134  err=xnull: fatal: 除零
c7c             compiled rc=0    out=MAIN-SHOULD-NOT-RUN
c7d             interp   rc=134  err=xnull: fatal: 除零
c7d             compiled rc=0    out=MAIN-SHOULD-NOT-RUN a=0
e3_dup_overload interp/compiled rc=1 err=error[ENTRY-002]: 重复入口 main：发现 2 个 main 声明
```

P2 观察：

```
c7e   interp rc=134 / compiled rc=255
c4    interp "true top 3" / compiled "1 top 3"
c8    interp "true|true|false" / compiled "true|1|0"
c9    interp "s=true|raw=true" / compiled "s=1|raw=1"
```

---

## 四、缺陷状态

| # | 缺陷 | 状态 | 严重度 |
|---|---|---|---|
| D-01 | 初始化除零在编译路径不终止，入口被调用（常量折叠/运行期两形态） | **OPEN** | P1 |
| D-02 | `private`/`protected` 入口未拒绝 | **FIXED** | — |
| D-03 | 泛型入口未拒绝 | **FIXED** | — |
| D-04 | 非匹配 `main` 重载误判重复入口 | **OPEN** | P1 |
| D-05 | interp 初始化前向引用/调用函数报未定义 | **FIXED** | — |
| D-06 | fatal 退出码 interp 134 vs compiled 255 | **OPEN** | P2 |
| D-07 | `str(Bool)`/`print(Bool)` 输出 `true` vs `1`/`0` | **OPEN** | P2 |

---

## 五、已跑命令与结果

```bash
cd /Users/vjs/Desktop/XNull-Lang
SHA=$(git rev-parse main)   # 7262ff0
git archive "$SHA" | tar -x -C $T/src
( cd $T/src/impl && go build -o $T/xnull ./cmd/xnull )
bash evidence/M1-ENTRY-01-qa/run.sh   # A/B/C/D/E 共 31 用例 × 2 路径
bash evidence/M1-ENTRY-01-qa/run2.sh  # c7/c8/c9/c10/c11
# 追加：c7b/c7c/c7d/c7e/e12/e13/e14
# 示例双路径 10/10
```

示例双路径原样输出：`DUAL_OK=10 DUAL_BAD=0`。

---

## 六、证据路径

- 本轮日志：`evidence/QA1-verify-2026-11-07/entry-run1.log`、`entry-run2.log`、`entry-run3.log`、`entry-examples.log`
- 用例与运行器：`evidence/M1-ENTRY-01-qa/{cases,run.sh,run2.sh}`
- 被测 sha：`7262ff0`（导出树构建）
- 历史验收：`收件箱/回执箱/CEO3/验收-M1-ENTRY-01.md`

---

## 七、放行条件（复验判据）

1. D-01：`Int a = 1/0` 常量与运行期两形态，编译路径必须终止且 main 零输出；退出码与 interp 同口径（可同卡修 D-06）。
2. D-04：`main()` + `main(Int)` 不得报重复入口；入口取匹配签名，其余为普通函数。
3. D-07：`str(Bool)`/`print(Bool)` 两路径同文案（`true`/`false`）。
4. 复验从干净导出副本重跑 `run.sh`/`run2.sh` + 追加 7 例 + 示例 10/10。

D-06/D-07 不单独阻断，但需在对应锚点闭环。
| C-10 初始化 fatal 终止（编译 + 解释） | **PASS 6/6**：双路径 `rc=134`，入口零输出 |
| C-13 非匹配 `main` 重载（入口在前） | **PASS**：`main()` + `main(Int)` 双路径输出 `entry` |
| C-13 非匹配 `main` 重载（**重载在前**） | **PASS**：双路径 `rc=0`，`main(41)` 输出 `42` |
| C-13 从其他函数调用重载（重载在前） | **PASS**：双路径 `rc=0`，输出 `42` |
| 回归：e10/e11/e12 负例、e13/e14、重复入口 | **PASS** |

**判定：PASS。** `bf03f5f` 消除了声明顺序依赖：非匹配 `main` 无论声明在入口之前还是之后，都分配独立 C 名，不再误报 `重复入口 main`。

---

## 二、C-10 逐项（PASS）

| # | 用例 | 初始化形态 | interp | compiled | 判定 |
|---:|---|---|---|---|---|
| 1 | `c3_init_fatal` | 常量 `1 / 0` | rc=134，无输出 | rc=134，无输出 | PASS |
| 2 | `c7b` | 运行期 `10 / d` | rc=134，无输出 | rc=134，无输出 | PASS |
| 3 | `c7_runtime_divzero` | `d=0; 10/d` | rc=134，无输出 | rc=134，无输出 | PASS |
| 4 | `c7c_runtime_divzero` | 顶层字段在入口声明之后 | rc=134，无输出 | rc=134，无输出 | PASS |
| 5 | `c7d_args_divzero` | 初始化式调用后置函数 | rc=134，无输出 | rc=134，无输出 | PASS |
| 6 | `c7e_runtime_divzero` | `s.length()-1` 得 0 | rc=134，无输出 | rc=134，无输出 | PASS |

stderr 均为 `xnull: fatal: 除零`。

---

## 三、C-13 逐项（PASS）

### 3.1 入口在前

`e3_dup_overload.x`：`main()` 在前、`main(Int)` 在后。

| 路径 | rc | stdout | 判定 |
|---|---:|---|---|
| `run --interp` | 0 | `entry` | PASS |
| `run`（编译） | 0 | `entry` | PASS |

### 3.2 重载在前（本轮修复点）

`c13_call_overload.x`：

```x
static Int main(Int x) { return x + 1 }
static Int main() {
    print(main(41))
    return 0
}
```

| 路径 | rc | stdout | 判定 |
|---|---:|---|---|
| `run --interp` | 0 | `42` | PASS |
| `run`（编译） | 0 | `42` | PASS |

同形态 `c13_call_helper.x`（从另一个函数调用重载）：双路径均 `42`，PASS。  
`c13_entry_first_call.x`（入口在前并调用重载）：双路径均 `42`，PASS。

### 3.3 负例回归

| 用例 | 双路径实测 | 判定 |
|---|---|---|
| `e10_private_main` | `ENTRY-003`，rc=1 | PASS |
| `e11_generic_main` | `ENTRY-003`，rc=1 | PASS |
| `e12_protected_main` | `ENTRY-003`，rc=1 | PASS |
| `e13_public_main` | rc=3，`pub` | PASS |
| `e14_int_args_noreturn` | `DA-103`，rc=1 | PASS |
| 两个匹配签名入口 | `ENTRY-002`，rc=1 | PASS |

---

## 四、边界（不阻断本条）

1. **同参数个数的多个非匹配重载**：`main(Int)` + `main(String)` 同时存在时，编译路径按参数个数分派会选错 C 名，C 编译报类型不匹配。该能力属 §4.4/§8.2 一般重载（M4.5+），不在 C-13“重载在前”本条；本轮已记录，未计入 PASS 依据。
2. 工程清单指定入口文件/入口包（§11.4 清单模式）：工程配置规范未落地。
3. 非默认包 `main`：多包编译未支持（PKG-01 范围）。
4. 默认参数/可变参数入口：语法层无该构造。

---

## 五、回归

| 项 | 命令 | 结果 |
|---|---|---|
| C-10/C-13 新增用例 | `go test ./internal/cli -run 'TestEntryMainOverloadIsOrdinary|TestEntryInitDivZeroFatal' -count=1 -v` | `TestEntryMainOverloadIsOrdinary`（入口在前/重载在前）与 `TestEntryInitDivZeroFatal`（常量/运行期）全 PASS |
| `go vet ./...` | — | exit 0 |
| `go test ./...` | — | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 计数 13（golden 10）。由 `status.tsv` 的 GEN/NEG/PKG 翻 PASS 引起，与本锚点无关。 |

---

## 六、证据

- 复验目录：`evidence/M1-ENTRY-01-reverify-91c89c0/`
  - `sha.txt`：main `91c89c0`、`bf03f5f`、二进制工具链
  - `command.txt`
  - `cases/`、`cases.txt`：16 例源码
  - `out/matrix.tsv`：逐例双路径 rc/stdout/stderr
  - `out/<case>.<mode>.{out,err}`
  - `cli-entry-tests.log`：新增 Go 用例
  - `full-test.log`
- 前一轮（`d620ea5`，FAIL）：`evidence/M1-ENTRY-01-reverify-d620ea5/`
- 断言依据：`XNull解决方案-第1部分-基础语法-v3.3.0.md` §11.2、§11.3、§11.4
